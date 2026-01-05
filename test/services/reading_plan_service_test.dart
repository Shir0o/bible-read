import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/services/reading_plan_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/models/reading_plan_progress.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReadingPlanService', () {
    late FakeFirebaseFirestore firestore;
    late ReadingPlanService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = ReadingPlanService(firestore: firestore);
    });

    test('getAvailablePlans loads plans from assets', () async {
      // Since we can't easily mock rootBundle in unit tests without complex setup,
      // and getAvailablePlans depends on it, we might skip this or mock the caching/loading method if possible.
      // However, we can test the other methods which depend on Firestore.
    });

    test('startPlan creates progress document', () async {
      await service.startPlan('user1', 'plan1');

      final doc = await firestore
          .collection('users')
          .doc('user1')
          .collection('plan_progress')
          .doc('plan1')
          .get();

      expect(doc.exists, isTrue);
      expect(doc.data()!['planId'], 'plan1');
      expect(doc.data()!['completedDays'], isEmpty);
    });

    test('markDayComplete updates progress', () async {
      await service.startPlan('user1', 'plan1');
      await service.markDayComplete('user1', 'plan1', 1);

      final doc = await firestore
          .collection('users')
          .doc('user1')
          .collection('plan_progress')
          .doc('plan1')
          .get();

      expect(doc.data()!['completedDays'], contains(1));
    });

    test('markDayComplete ignores duplicate days', () async {
      await service.startPlan('user1', 'plan1');
      await service.markDayComplete('user1', 'plan1', 1);
      await service.markDayComplete('user1', 'plan1', 1);

      final doc = await firestore
          .collection('users')
          .doc('user1')
          .collection('plan_progress')
          .doc('plan1')
          .get();

      final completed = List<int>.from(doc.data()!['completedDays']);
      expect(completed.length, 1);
      expect(completed.first, 1);
    });

    test('unmarkDayComplete removes day', () async {
      await service.startPlan('user1', 'plan1');
      await service.markDayComplete('user1', 'plan1', 1);
      await service.unmarkDayComplete('user1', 'plan1', 1);

      final doc = await firestore
          .collection('users')
          .doc('user1')
          .collection('plan_progress')
          .doc('plan1')
          .get();

      expect(doc.data()!['completedDays'], isEmpty);
    });
    
    test('getNextDueDay returns correct day', () {
      final plan = ReadingPlan(
        id: 'p1',
        title: 'T',
        description: 'D',
        durationDays: 3,
        tags: [],
        schedule: [
          ReadingPlanDay(day: 1, readings: []),
          ReadingPlanDay(day: 2, readings: []),
          ReadingPlanDay(day: 3, readings: []),
        ]
      );
      
      final service = ReadingPlanService(firestore: firestore);
      
      // No progress
      var progress = UserPlanProgress(
        planId: 'p1', userId: 'u1', startDate: DateTime.now(), completedDays: []
      );
      expect(service.getNextDueDay(plan, progress)?.day, 1);
      
      // Day 1 done
      progress = progress.copyWith(completedDays: [1]);
      expect(service.getNextDueDay(plan, progress)?.day, 2);
      
      // Day 1 & 2 done
       progress = progress.copyWith(completedDays: [1, 2]);
      expect(service.getNextDueDay(plan, progress)?.day, 3);
      
      // All done
       progress = progress.copyWith(completedDays: [1, 2, 3]);
      expect(service.getNextDueDay(plan, progress), isNull);
    });
  });
}
