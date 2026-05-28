import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/seasonal_challenge.dart';
import 'package:bible_read/models/seasonal_reward.dart';
import 'package:bible_read/pages/seasonal_challenges_page.dart';
import 'package:bible_read/services/seasonal_challenge_service.dart';
import 'package:bible_read/widgets/seasonal_challenge_card.dart';

class _FailingChallengeService extends SeasonalChallengeService {
  _FailingChallengeService({required super.firestore});

  @override
  Stream<List<SeasonalChallenge>> streamChallenges(String seasonId) =>
      Stream<List<SeasonalChallenge>>.error(Exception('load failed'));
}

Future<void> _seedSeason({
  required FakeFirebaseFirestore firestore,
  required String seasonId,
  required DateTime start,
  required DateTime end,
}) async {
  await firestore.collection('seasons').doc(seasonId).set({
    'title': 'Spring Season',
    'description': 'Grow together.',
    'startDate': Timestamp.fromDate(start),
    'endDate': Timestamp.fromDate(end),
  });
}

Future<void> _seedChallenge({
  required FakeFirebaseFirestore firestore,
  required String seasonId,
  required String challengeId,
  int goal = 10,
}) async {
  await firestore
      .collection('seasons')
      .doc(seasonId)
      .collection('challenges')
      .doc(challengeId)
      .set({
        'seasonId': seasonId,
        'title': 'Read $goal chapters',
        'description': 'Stay consistent every day.',
        'metric': 'chapters',
        'goal': goal,
        'reward': const SeasonalReward(
          id: 'r1',
          type: 'points',
          title: 'Bonus Points',
          description: 'Extra rewards for reading.',
          amount: 25,
        ).toFirestore(),
      });
}

String _formatDay(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SeasonalChallengesPage', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late DateTime now;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'user-1'),
        signedIn: true,
      );
      now = DateTime.now();
    });

    testWidgets('renders active challenges for the current season', (
      tester,
    ) async {
      const seasonId = 'spring';
      await _seedSeason(
        firestore: firestore,
        seasonId: seasonId,
        start: now.subtract(const Duration(days: 1)),
        end: now.add(const Duration(days: 30)),
      );
      await _seedChallenge(
        firestore: firestore,
        seasonId: seasonId,
        challengeId: 'c1',
        goal: 15,
      );

      final service = SeasonalChallengeService(
        firestore: firestore,
        clock: () => now,
        claimRewardFn: ({required seasonId, required challengeId}) async {
          await firestore
              .collection('users')
              .doc('user-1')
              .collection('seasonChallenges')
              .doc('${seasonId}_$challengeId')
              .set({
                'rewardClaimedAt': Timestamp.fromDate(now),
              }, SetOptions(merge: true));
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SeasonalChallengesPage(auth: auth, service: service),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Spring Season'), findsOneWidget);
      expect(find.text('Read 15 chapters'), findsOneWidget);
      expect(find.byType(SeasonalChallengeCard), findsOneWidget);
    });

    testWidgets('claiming a reward updates progress and shows snackbar', (
      tester,
    ) async {
      const seasonId = 'spring';
      const challengeId = 'c1';
      await _seedSeason(
        firestore: firestore,
        seasonId: seasonId,
        start: now.subtract(const Duration(days: 3)),
        end: now.add(const Duration(days: 14)),
      );
      await _seedChallenge(
        firestore: firestore,
        seasonId: seasonId,
        challengeId: challengeId,
        goal: 5,
      );
      final dayKey = _formatDay(now);
      await firestore
          .collection('users')
          .doc('user-1')
          .collection('seasonChallenges')
          .doc('${seasonId}_$challengeId')
          .set({
            'uid': 'user-1',
            'seasonId': seasonId,
            'challengeId': challengeId,
            'totalProgress': 5,
            'dailyProgress': {dayKey: 5},
            'completedAt': Timestamp.fromDate(
              now.subtract(const Duration(days: 1)),
            ),
          });

      final service = SeasonalChallengeService(
        firestore: firestore,
        clock: () => now,
        claimRewardFn: ({required seasonId, required challengeId}) async {
          await firestore
              .collection('users')
              .doc('user-1')
              .collection('seasonChallenges')
              .doc('${seasonId}_$challengeId')
              .set({
                'rewardClaimedAt': Timestamp.fromDate(now),
              }, SetOptions(merge: true));

          await firestore
              .collection('users')
              .doc('user-1')
              .collection('seasonRewards')
              .doc('${seasonId}_$challengeId')
              .set({'claimedAt': Timestamp.fromDate(now)});
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SeasonalChallengesPage(auth: auth, service: service),
        ),
      );

      await tester.pumpAndSettle();

      final claimButton = find.widgetWithText(ElevatedButton, 'Claim reward');
      expect(claimButton, findsOneWidget);

      await tester.tap(claimButton);
      await tester.pumpAndSettle();

      expect(find.text('Reward claimed!'), findsOneWidget);

      final progressDoc = await firestore
          .collection('users')
          .doc('user-1')
          .collection('seasonChallenges')
          .doc('${seasonId}_$challengeId')
          .get();
      expect(progressDoc.data()?['rewardClaimedAt'], isNotNull);
    });

    testWidgets('shows error message when challenge stream fails', (
      tester,
    ) async {
      const seasonId = 'spring';
      await _seedSeason(
        firestore: firestore,
        seasonId: seasonId,
        start: now.subtract(const Duration(days: 2)),
        end: now.add(const Duration(days: 20)),
      );

      final service = _FailingChallengeService(firestore: firestore);

      await tester.pumpWidget(
        MaterialApp(
          home: SeasonalChallengesPage(auth: auth, service: service),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Failed to load seasonal challenges.'), findsOneWidget);
    });
  });
}
