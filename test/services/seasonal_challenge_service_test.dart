import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/seasonal_challenge.dart';
import 'package:bible_read/models/seasonal_challenge_progress.dart';
import 'package:bible_read/models/seasonal_reward.dart';
import 'package:bible_read/services/seasonal_challenge_service.dart';

void main() {
  group('SeasonalChallengeService', () {
    late FakeFirebaseFirestore firestore;
    late SeasonalChallengeService service;
    late DateTime now;

    String dayKey(DateTime date) {
      final year = date.year.toString().padLeft(4, '0');
      final month = date.month.toString().padLeft(2, '0');
      final day = date.day.toString().padLeft(2, '0');
      return '$year-$month-$day';
    }

    setUp(() {
      firestore = FakeFirebaseFirestore();
      now = DateTime(2024, 5, 10, 12);
      service = SeasonalChallengeService(
        firestore: firestore,
        clock: () => now,
      );
    });

    test(
      'fetchActiveSeason returns the season containing the current date',
      () async {
        await firestore
            .collection(SeasonalChallengePaths.seasons)
            .doc('past')
            .set({
              'title': 'Past Season',
              'description': 'Already finished',
              'startDate': Timestamp.fromDate(DateTime(2023, 1, 1)),
              'endDate': Timestamp.fromDate(DateTime(2023, 1, 31)),
            });
        await firestore
            .collection(SeasonalChallengePaths.seasons)
            .doc('spring2024')
            .set({
              'title': 'Spring 2024',
              'description': 'Active season',
              'startDate': Timestamp.fromDate(DateTime(2024, 5, 1)),
              'endDate': Timestamp.fromDate(DateTime(2024, 5, 31)),
            });

        final season = await service.fetchActiveSeason();

        expect(season, isNotNull);
        expect(season!.id, 'spring2024');
      },
    );

    test('streamChallenges surfaces reward metadata', () async {
      await firestore
          .collection(SeasonalChallengePaths.seasons)
          .doc('summer2024')
          .set({
            'title': 'Summer 2024',
            'description': 'Summer fun',
            'startDate': Timestamp.fromDate(DateTime(2024, 6, 1)),
            'endDate': Timestamp.fromDate(DateTime(2024, 6, 30)),
          });
      await firestore
          .collection(SeasonalChallengePaths.seasons)
          .doc('summer2024')
          .collection(SeasonalChallengePaths.challenges)
          .doc('memorize')
          .set({
            'title': 'Memorize verses',
            'description': 'Commit verses to memory',
            'metric': 'verses',
            'goal': 3,
            'reward': {
              'id': 'verse_badge',
              'type': 'badge',
              'title': 'Verse Badge',
              'description': 'Reward for memorizing verses',
              'amount': 1,
            },
          });

      final challenges = await service.streamChallenges('summer2024').first;

      expect(challenges, hasLength(1));
      final challenge = challenges.first;
      expect(challenge.title, 'Memorize verses');
      expect(challenge.reward, isA<SeasonalReward>());
      expect(challenge.reward?.title, 'Verse Badge');
    });

    test(
      'incrementDailyProgress caps progress at the goal and marks completion',
      () async {
        const challenge = SeasonalChallenge(
          id: 'read',
          seasonId: 'spring2024',
          title: 'Read three chapters',
          description: 'Finish three chapters',
          metric: 'chapters',
          goal: 3,
          reward: SeasonalReward(
            id: 'badge',
            type: 'badge',
            title: 'Reading Badge',
            description: 'Awarded for reading',
            amount: 1,
          ),
        );

        final first = await service.incrementDailyProgress(
          uid: 'user1',
          challenge: challenge,
          amount: 2,
        );

        expect(first.totalProgress, 2);
        expect(first.completedAt, isNull);
        expect(first.dailyProgress[dayKey(now)], 2);

        now = now.add(const Duration(hours: 1));

        final second = await service.incrementDailyProgress(
          uid: 'user1',
          challenge: challenge,
          amount: 2,
        );

        expect(second.totalProgress, 3);
        expect(second.completedAt, isNotNull);
        expect(second.dailyProgress[dayKey(now)], 3);

        final stored = await firestore
            .collection(SeasonalChallengePaths.users)
            .doc('user1')
            .collection(SeasonalChallengePaths.userSeasonChallenges)
            .doc('spring2024_read')
            .get();
        expect(stored.data()?['totalProgress'], 3);
        expect(stored.data()?['completedAt'], isA<Timestamp>());
      },
    );

    test('streamProgress emits updates after increments', () async {
      const challenge = SeasonalChallenge(
        id: 'pray',
        seasonId: 'spring2024',
        title: 'Pray daily',
        description: 'Spend time in daily prayer',
        metric: 'days',
        goal: 2,
      );

      final future = service
          .streamProgress(
            uid: 'user2',
            seasonId: 'spring2024',
            challengeId: 'pray',
          )
          .where((event) => event != null)
          .cast<SeasonalChallengeProgress>()
          .first;

      await service.incrementDailyProgress(uid: 'user2', challenge: challenge);

      final progress = await future;
      expect(progress.totalProgress, 1);
    });

    test('claimReward invokes callable and refreshes state', () async {
      const challenge = SeasonalChallenge(
        id: 'share',
        seasonId: 'spring2024',
        title: 'Share with friends',
        description: 'Share the app with friends',
        metric: 'shares',
        goal: 1,
      );

      final progress = await service.incrementDailyProgress(
        uid: 'user3',
        challenge: challenge,
      );

      final calls = <Map<String, String>>[];
      final claimingService = SeasonalChallengeService(
        firestore: firestore,
        clock: () => now,
        claimRewardFn: ({required seasonId, required challengeId}) async {
          calls.add({'seasonId': seasonId, 'challengeId': challengeId});
          await firestore
              .collection(SeasonalChallengePaths.users)
              .doc('user3')
              .collection(SeasonalChallengePaths.userSeasonChallenges)
              .doc('${seasonId}_$challengeId')
              .set({
                'rewardClaimedAt': Timestamp.fromDate(now),
              }, SetOptions(merge: true));
          await firestore
              .collection(SeasonalChallengePaths.users)
              .doc('user3')
              .collection(SeasonalChallengePaths.userSeasonRewards)
              .doc('${seasonId}_$challengeId')
              .set({'claimedAt': Timestamp.fromDate(now)});
        },
      );

      await claimingService.claimReward(uid: 'user3', progress: progress);

      expect(calls, [
        {'seasonId': 'spring2024', 'challengeId': 'share'},
      ]);

      final stored = await firestore
          .collection(SeasonalChallengePaths.users)
          .doc('user3')
          .collection(SeasonalChallengePaths.userSeasonChallenges)
          .doc('spring2024_share')
          .get();
      expect(stored.data()?['rewardClaimedAt'], isA<Timestamp>());

      final rewardDoc = await firestore
          .collection(SeasonalChallengePaths.users)
          .doc('user3')
          .collection(SeasonalChallengePaths.userSeasonRewards)
          .doc('spring2024_share')
          .get();
      expect(rewardDoc.exists, isTrue);
    });

    test(
      'incrementDailyProgress preserves reward metadata that already exists',
      () async {
        final claimedAt = Timestamp.fromDate(DateTime(2024, 5, 9));
        final doc = firestore
            .collection(SeasonalChallengePaths.users)
            .doc('user4')
            .collection(SeasonalChallengePaths.userSeasonChallenges)
            .doc('spring2024_reflect');
        await doc.set({
          'uid': 'user4',
          'seasonId': 'spring2024',
          'challengeId': 'reflect',
          'dailyProgress': {'2024-05-09': 3},
          'totalProgress': 3,
          'rewardClaimedAt': claimedAt,
        });

        const challenge = SeasonalChallenge(
          id: 'reflect',
          seasonId: 'spring2024',
          title: 'Reflect on verses',
          description: 'Write reflections on passages',
          metric: 'entries',
          goal: 5,
        );

        final progress = await service.incrementDailyProgress(
          uid: 'user4',
          challenge: challenge,
          amount: 2,
        );

        expect(progress.rewardClaimedAt, claimedAt.toDate());
      },
    );
  });
}
