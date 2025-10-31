import 'package:bible_read/models/exercise_challenge.dart';
import 'package:bible_read/services/exercise_tracker_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExerciseTrackerService', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late ExerciseTrackerService service;
    late MockUser user;
    late DateTime now;

    String dayKey(DateTime date) =>
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    setUp(() {
      now = DateTime(2024, 5, 10, 8, 30);
      user = MockUser(uid: 'user-1', email: 'user@test.com');
      auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      firestore = FakeFirebaseFirestore();
      service = ExerciseTrackerService(
        firestore: firestore,
        auth: auth,
        clock: () => now,
      );
    });

    test(
      'upsertChallenge creates challenge document with timestamps',
      () async {
        final created = await service.upsertChallenge(
          ExerciseChallenge(
            id: '',
            uid: '',
            name: 'Morning Run',
            unit: 'minutes',
            dailyGoal: 30,
            targetType: ExerciseTargetType.atLeast,
            totalTarget: 600,
          ),
        );

        expect(created.id, isNotEmpty);
        expect(created.uid, user.uid);
        expect(created.createdAt, now);
        expect(created.updatedAt, now);

        final doc = await firestore
            .collection(ExerciseTrackerPaths.users)
            .doc(user.uid)
            .collection(ExerciseTrackerPaths.challenges)
            .doc(created.id)
            .get();

        expect(doc.exists, isTrue);
        final data = doc.data();
        expect(data?['name'], 'Morning Run');
        expect(data?['unit'], 'minutes');
        expect(data?['dailyGoal'], 30);
        expect(data?['targetType'], ExerciseTargetType.atLeast.name);
        expect(data?['totalTarget'], 600);
        expect((data?['createdAt'] as Timestamp).toDate(), now);
        expect((data?['updatedAt'] as Timestamp).toDate(), now);
      },
    );

    test(
      'recordDailyAmount increments totals and reports goal completion',
      () async {
        final challenge = await service.upsertChallenge(
          ExerciseChallenge(
            id: '',
            uid: '',
            name: 'Rowing',
            unit: 'minutes',
            dailyGoal: 30,
            targetType: ExerciseTargetType.atLeast,
          ),
        );

        final first = await service.recordDailyAmount(
          challenge: challenge,
          amount: 20,
        );
        expect(first.totalForChallenge(challenge.id), 20);

        now = now.add(const Duration(hours: 2));
        final second = await service.recordDailyAmount(
          challenge: challenge,
          amount: 15,
        );
        expect(second.totalForChallenge(challenge.id), 35);

        final progressDoc = await firestore
            .collection(ExerciseTrackerPaths.users)
            .doc(user.uid)
            .collection(ExerciseTrackerPaths.progress)
            .doc(dayKey(now))
            .get();

        expect(progressDoc.exists, isTrue);
        expect(progressDoc.data()?['totals'][challenge.id], 35);

        final summaries = await service.fetchChallengeSummaries(uid: user.uid);
        expect(summaries, hasLength(1));
        final summary = summaries.first;
        expect(summary.todayTotal, 35);
        expect(summary.goalMetToday, isTrue);
        expect(summary.totalRecorded, 35);
        expect(summary.recentTotals[dayKey(now)], 35);
      },
    );

    test('fetchChallengeSummaries resets streak when day missed', () async {
      final challenge = await service.upsertChallenge(
        ExerciseChallenge(
          id: '',
          uid: '',
          name: 'Plank',
          unit: 'minutes',
          dailyGoal: 5,
          targetType: ExerciseTargetType.atLeast,
        ),
      );

      final fiveDaysAgo = now.subtract(const Duration(days: 5));
      final fourDaysAgo = now.subtract(const Duration(days: 4));
      await service.recordDailyAmount(
        challenge: challenge,
        amount: 5,
        date: fiveDaysAgo,
      );
      await service.recordDailyAmount(
        challenge: challenge,
        amount: 5,
        date: fourDaysAgo,
      );

      final summaries = await service.fetchChallengeSummaries(uid: user.uid);
      expect(summaries, hasLength(1));
      final summary = summaries.first;
      expect(summary.goalMetToday, isFalse);
      expect(summary.currentStreak, 0);
      expect(summary.recentTotals[dayKey(fiveDaysAgo)], 5);
      expect(summary.recentTotals[dayKey(fourDaysAgo)], 5);
    });

    test(
      'fetchChallengeSummaries preserves streak before logging today',
      () async {
        final challenge = await service.upsertChallenge(
          ExerciseChallenge(
            id: '',
            uid: '',
            name: 'Jogging',
            unit: 'minutes',
            dailyGoal: 20,
            targetType: ExerciseTargetType.atLeast,
          ),
        );

        final yesterday = now.subtract(const Duration(days: 1));
        final twoDaysAgo = now.subtract(const Duration(days: 2));

        await service.recordDailyAmount(
          challenge: challenge,
          amount: 25,
          date: twoDaysAgo,
        );
        await service.recordDailyAmount(
          challenge: challenge,
          amount: 25,
          date: yesterday,
        );

        final summaries = await service.fetchChallengeSummaries(uid: user.uid);
        expect(summaries, hasLength(1));
        final summary = summaries.first;
        expect(summary.goalMetToday, isFalse);
        expect(summary.currentStreak, 2);
      },
    );

    test(
      'fetchChallengeSummaries reports goal state for multiple challenges',
      () async {
        final run = await service.upsertChallenge(
          ExerciseChallenge(
            id: '',
            uid: '',
            name: 'Run',
            unit: 'minutes',
            dailyGoal: 30,
            targetType: ExerciseTargetType.atLeast,
            totalTarget: 300,
          ),
        );
        final sugar = await service.upsertChallenge(
          ExerciseChallenge(
            id: '',
            uid: '',
            name: 'Sugar',
            unit: 'grams',
            dailyGoal: 25,
            targetType: ExerciseTargetType.atMost,
          ),
        );
        final pushUps = await service.upsertChallenge(
          ExerciseChallenge(
            id: '',
            uid: '',
            name: 'Push Ups',
            unit: 'reps',
            dailyGoal: 40,
            targetType: ExerciseTargetType.exactly,
          ),
        );

        await service.recordDailyAmount(challenge: run, amount: 35);
        await service.recordDailyAmount(challenge: sugar, amount: 30);
        await service.recordDailyAmount(challenge: pushUps, amount: 38);
        await service.recordDailyAmount(challenge: pushUps, amount: 2);

        final summaries = await service.fetchChallengeSummaries(uid: user.uid);
        expect(summaries.length, 3);
        final byName = {
          for (final summary in summaries) summary.challenge.name: summary,
        };

        final runSummary = byName['Run'];
        final sugarSummary = byName['Sugar'];
        final pushUpSummary = byName['Push Ups'];

        expect(runSummary, isNotNull);
        expect(runSummary!.goalMetToday, isTrue);
        expect(runSummary.todayTotal, 35);
        expect(runSummary.totalRecorded, 35);
        expect(runSummary.recentTotals[dayKey(now)], 35);
        expect(runSummary.challenge.unit, 'minutes');

        expect(sugarSummary, isNotNull);
        expect(sugarSummary!.goalMetToday, isFalse);
        expect(sugarSummary.todayTotal, 30);
        expect(sugarSummary.challenge.unit, 'grams');

        expect(pushUpSummary, isNotNull);
        expect(pushUpSummary!.goalMetToday, isTrue);
        expect(pushUpSummary.todayTotal, 40);
        expect(pushUpSummary.challenge.unit, 'reps');
      },
    );
  });
}
