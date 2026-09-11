import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/reading_plan_progress.dart';

void main() {
  group('UserPlanProgress', () {
    test('toFirestore serializes all fields including soft delete fields', () {
      final now = DateTime(2026, 9, 10, 10, 0);
      final deleteAfter = now.add(const Duration(days: 30));

      final progress = UserPlanProgress(
        planId: 'p1',
        userId: 'u1',
        startDate: now,
        completedDays: [1, 2],
        lastReadDate: now,
        isArchived: true,
        deletedAt: now,
        deleteAfter: deleteAfter,
        preDeleteState: 'active',
      );

      final map = progress.toFirestore();

      expect(map['planId'], 'p1');
      expect(map['userId'], 'u1');
      expect((map['startDate'] as Timestamp).toDate(), now);
      expect(map['completedDays'], [1, 2]);
      expect((map['lastReadDate'] as Timestamp).toDate(), now);
      expect(map['isArchived'], isTrue);
      expect((map['deletedAt'] as Timestamp).toDate(), now);
      expect((map['deleteAfter'] as Timestamp).toDate(), deleteAfter);
      expect(map['preDeleteState'], 'active');
    });

    test('toFirestore writes nulls for unpopulated nullable fields', () {
      final now = DateTime(2026, 9, 10, 10, 0);
      final progress = UserPlanProgress(
        planId: 'p1',
        userId: 'u1',
        startDate: now,
        completedDays: const [],
      );

      final map = progress.toFirestore();

      expect(map['lastReadDate'], isNull);
      expect(map['isArchived'], isFalse);
      expect(map['deletedAt'], isNull);
      expect(map['deleteAfter'], isNull);
      expect(map['preDeleteState'], isNull);
    });
  });
}
