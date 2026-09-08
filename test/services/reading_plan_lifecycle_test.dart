// Lifecycle: archive, 30-day trash, restore, purge (#776).
//
// External behavior only: archiving hides a plan from active lists and shows
// it in the archive; trashing hides it everywhere and lists it with a
// countdown; restoring puts it back to its pre-deletion state; purging
// removes it for good; re-enrolling a trashed plan collides.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/models/reading_plan_progress.dart';
import 'package:bible_read/services/reading_plan_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReadingPlanService lifecycle', () {
    late FakeFirebaseFirestore firestore;
    late ReadingPlanService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = ReadingPlanService(firestore: firestore);
    });

    Future<void> seedStartedPlan(String planId) async {
      await firestore.collection('custom_plans').doc(planId).set({
        'id': planId,
        'title': 'Morning Light',
        'description': 'A gentle daily reading',
        'durationDays': 3,
        'tags': <String>[],
        'schedule': [
          {
            'day': 1,
            'readings': ['Gen 1']
          },
          {
            'day': 2,
            'readings': ['Gen 2']
          },
          {
            'day': 3,
            'readings': ['Gen 3']
          },
        ],
        'userId': 'u1',
      });
      await service.startPlan('u1', planId, startDate: DateTime(2026, 9, 1));
      await service.markDayComplete('u1', planId, 1);
    }

    test('archivePlan hides the plan from active and shows it in archive',
        () async {
      await seedStartedPlan('p1');

      final activeBefore = await service.getActivePlans('u1').first;
      expect(activeBefore, hasLength(1));

      await service.archivePlan('u1', 'p1');

      expect(await service.getActivePlans('u1').first, isEmpty);
      final archived = await service.getArchivedPlans('u1').first;
      expect(archived, hasLength(1));
      expect(archived.single.completedDays, [1]);
    });

    test('unarchivePlan returns the plan with its progress intact', () async {
      await seedStartedPlan('p1');
      await service.archivePlan('u1', 'p1');

      await service.unarchivePlan('u1', 'p1');

      final active = await service.getActivePlans('u1').first;
      expect(active, hasLength(1));
      expect(active.single.completedDays, [1]);
      final progress = await service.getPlanProgress('u1', 'p1').first;
      expect(progress?.deletedAt, isNull);
      expect(progress?.isArchived, isFalse);
    });

    test(
        'softDeletePlan hides the plan from active and archive lists and '
        'sets the 30-day deadline', () async {
      await seedStartedPlan('p1');

      final now = DateTime(2026, 9, 8, 12);
      await service.softDeletePlan('u1', 'p1', now: now);

      expect(await service.getActivePlans('u1').first, isEmpty);
      expect(await service.getArchivedPlans('u1').first, isEmpty);

      final deleted = await service.getDeletedPlans('u1').first;
      expect(deleted, hasLength(1));
      expect(deleted.single.deleteAfter, now.add(const Duration(days: 30)));
      expect(deleted.single.preDeleteState, 'active');
      // Progress survives the move to the trash.
      expect(deleted.single.completedDays, [1]);
    });

    test('softDeletePlan records archived state for pre-deletion restore',
        () async {
      await seedStartedPlan('p1');
      await service.archivePlan('u1', 'p1');

      await service.softDeletePlan('u1', 'p1');

      final deleted = await service.getDeletedPlans('u1').first;
      expect(deleted.single.preDeleteState, 'archived');
      expect(deleted.single.isArchived, isTrue);
    });

    test('restorePlan returns an active-deleted plan to the active list',
        () async {
      await seedStartedPlan('p1');
      await service.softDeletePlan('u1', 'p1');

      await service.restorePlan('u1', 'p1');

      final active = await service.getActivePlans('u1').first;
      expect(active, hasLength(1));
      expect(active.single.completedDays, [1]);
      expect(active.single.deletedAt, isNull);
      expect(await service.getDeletedPlans('u1').first, isEmpty);
    });

    test('restorePlan returns an archived-deleted plan to the archive',
        () async {
      await seedStartedPlan('p1');
      await service.archivePlan('u1', 'p1');
      await service.softDeletePlan('u1', 'p1');

      await service.restorePlan('u1', 'p1');

      // Back to exactly where it was: archived, not active, not trashed.
      expect(await service.getActivePlans('u1').first, isEmpty);
      final archived = await service.getArchivedPlans('u1').first;
      expect(archived, hasLength(1));
      expect(await service.getDeletedPlans('u1').first, isEmpty);
      final progress = await service.getPlanProgress('u1', 'p1').first;
      expect(progress?.isArchived, isTrue);
      expect(progress?.deletedAt, isNull);
    });

    test('permanentlyDeletePlan removes the document entirely', () async {
      await seedStartedPlan('p1');
      await service.softDeletePlan('u1', 'p1');

      await service.permanentlyDeletePlan('u1', 'p1');

      final doc = await firestore
          .collection('users')
          .doc('u1')
          .collection('plan_progress')
          .doc('p1')
          .get();
      expect(doc.exists, isFalse);
      expect(await service.getDeletedPlans('u1').first, isEmpty);
    });

    test(
        'starting a soft-deleted plan collides; restoreDeleted keeps the '
        'old progress, a plain restart does not clobber silently', () async {
      await seedStartedPlan('p1');
      await service.softDeletePlan('u1', 'p1');

      // First start reports the collision instead of overwriting.
      final collision = await service.startPlan(
        'u1',
        'p1',
        startDate: DateTime(2026, 10, 1),
      );
      expect(collision, isNotNull);
      expect(collision!.completedDays, [1]);

      // The trashed record is untouched by the failed attempt.
      var trashed = await service.getDeletedPlans('u1').first;
      expect(trashed, hasLength(1));

      // Choosing restore brings the old progress back to life.
      await service.startPlan('u1', 'p1', restoreDeleted: true);
      final active = await service.getActivePlans('u1').first;
      expect(active, hasLength(1));
      expect(active.single.completedDays, [1]);
      expect(active.single.startDate, DateTime(2026, 9, 1));
      trashed = await service.getDeletedPlans('u1').first;
      expect(trashed, isEmpty);
    });

    test('starting a plan with no trashed record just starts', () async {
      final collision =
          await service.startPlan('u1', 'p2', startDate: DateTime(2026, 9, 1));
      expect(collision, isNull);
      final active = await service.getActivePlans('u1').first;
      expect(active, hasLength(1));
    });
  });
}
