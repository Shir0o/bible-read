import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/seasonal_challenge_progress.dart';

void main() {
  group('SeasonalChallengeProgress', () {
    test('fromFirestore parses totals and timestamps', () async {
      final firestore = FakeFirebaseFirestore();
      final updated = DateTime(2024, 5, 10, 12);
      final completed = DateTime(2024, 5, 12, 8);
      final ref = firestore
          .collection('users')
          .doc('uid')
          .collection('seasonChallenges')
          .doc('spring_read');
      await ref.set({
        'uid': 'uid',
        'seasonId': 'spring',
        'challengeId': 'read',
        'dailyProgress': {
          '2024-05-10': 2,
        },
        'totalProgress': 2,
        'updatedAt': Timestamp.fromDate(updated),
        'completedAt': Timestamp.fromDate(completed),
      });

      final snapshot = await ref.get();
      final progress = SeasonalChallengeProgress.fromFirestore(snapshot);

      expect(progress.id, 'spring_read');
      expect(progress.uid, 'uid');
      expect(progress.totalProgress, 2);
      expect(progress.dailyProgress['2024-05-10'], 2);
      expect(progress.updatedAt, updated);
      expect(progress.completedAt, completed);

      final serialized = progress.copyWith(
          totalProgress: 3, dailyProgress: {'2024-05-10': 3}).toFirestore();
      expect(serialized['totalProgress'], 3);
      expect(serialized['dailyProgress']['2024-05-10'], 3);
      expect(serialized['updatedAt'], isA<Timestamp>());
      expect(serialized['completedAt'], isA<Timestamp>());
    });

    test('copyWith preserves rewardClaimedAt when not provided', () {
      final rewardTime = DateTime(2024, 5, 13);
      final progress = SeasonalChallengeProgress(
        id: 'spring_read',
        uid: 'uid',
        seasonId: 'spring',
        challengeId: 'read',
        dailyProgress: const {'2024-05-10': 2},
        totalProgress: 2,
        rewardClaimedAt: rewardTime,
      );

      final updated = progress.copyWith(totalProgress: 3);
      expect(updated.rewardClaimedAt, rewardTime);
    });
  });
}
