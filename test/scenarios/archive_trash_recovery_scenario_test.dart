// Full arc for #776: an active plan is archived, trashed, restored, and
// finally purged — and a soft-deleted plan collides on re-enrollment.
//
// Runs against the real services over FakeFirebaseFirestore, following the
// group_lifecycle scenario style: no page, just the reader's data changing
// shape the way the hubs present it.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/services/reading_plan_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plan lifecycle arc: archive → trash → restore → trash → purge',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = ReadingPlanService(firestore: firestore);

    await firestore.collection('custom_plans').doc('p1').set({
      'id': 'p1',
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
    final started = await service.startPlan(
      'u1',
      'p1',
      startDate: DateTime(2026, 9, 1),
    );
    expect(started, isNull);
    await service.markDayComplete('u1', 'p1', 1);

    // 1. Archive: out of the active list, progress kept, visible in archive.
    await service.archivePlan('u1', 'p1');
    expect(await service.getActivePlans('u1').first, isEmpty);
    expect(
      (await service.getArchivedPlans('u1').first).single.completedDays,
      [1],
    );

    // 2. Trash it from the archive — the hub shows a countdown.
    final now = DateTime(2026, 9, 8, 12);
    await service.softDeletePlan('u1', 'p1', now: now);
    expect(await service.getArchivedPlans('u1').first, isEmpty);
    final trashed = await service.getDeletedPlans('u1').first;
    expect(trashed.single.preDeleteState, 'archived');
    final daysLeft = trashed.single.deleteAfter!.difference(now).inDays;
    expect(daysLeft, 30);

    // 3. Restore: back to exactly the archived state it had.
    await service.restorePlan('u1', 'p1');
    final restored = await service.getArchivedPlans('u1').first;
    expect(restored.single.completedDays, [1]);
    expect(await service.getDeletedPlans('u1').first, isEmpty);

    // 4. Trash again — this time restore through the re-enrollment collision
    //    path, as if the reader opened the plan and chose Restore Progress.
    await service.softDeletePlan('u1', 'p1', now: now);
    final collision = await service.startPlan(
      'u1',
      'p1',
      startDate: DateTime(2026, 10, 1),
    );
    expect(collision, isNotNull);
    await service.startPlan('u1', 'p1', restoreDeleted: true);
    // The restored record keeps the ORIGINAL start date and progress, and
    // returns to the state it had when trashed — archived.
    final restoredAgain = await service.getArchivedPlans('u1').first;
    expect(restoredAgain.single.startDate, DateTime(2026, 9, 1));
    expect(restoredAgain.single.completedDays, [1]);

    // 5. Final purge: the reader chooses Delete Permanently.
    await service.softDeletePlan('u1', 'p1', now: now);
    await service.permanentlyDeletePlan('u1', 'p1');
    final doc = await firestore
        .collection('users')
        .doc('u1')
        .collection('plan_progress')
        .doc('p1')
        .get();
    expect(doc.exists, isFalse);
    expect(await service.getDeletedPlans('u1').first, isEmpty);

    // 6. After the purge, starting fresh works with no collision.
    final fresh = await service.startPlan(
      'u1',
      'p1',
      startDate: DateTime(2026, 10, 1),
    );
    expect(fresh, isNull);
    final freshActive = await service.getActivePlans('u1').first;
    expect(freshActive.single.completedDays, isEmpty);
  });
}
