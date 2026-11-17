import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/models/user_preferences.dart';
import 'package:bible_read/services/active_reading_aggregator.dart';
import 'package:bible_read/services/catch_up_engine.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/plan_pace_service.dart';
import 'package:bible_read/services/reading_plan_service.dart';
import 'package:bible_read/services/user_preferences_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ReadingPlanService planService;
  late GroupService groupService;
  late PlanPaceService paceService;
  late UserPreferencesService prefsService;
  late ActiveReadingAggregator aggregator;

  const testPlan1 = ReadingPlan(
    id: 'p1',
    title: 'Genesis Plan',
    description: 'Read Genesis',
    durationDays: 3,
    tags: [],
    schedule: [
      ReadingPlanDay(day: 1, readings: ['Genesis 1']),
      ReadingPlanDay(day: 2, readings: ['Genesis 2']),
      ReadingPlanDay(day: 3, readings: ['Genesis 3']),
    ],
  );

  const testPlan2 = ReadingPlan(
    id: 'p2',
    title: 'Exodus Plan',
    description: 'Read Exodus',
    durationDays: 2,
    tags: [],
    schedule: [
      ReadingPlanDay(day: 1, readings: ['Exodus 1']),
      ReadingPlanDay(day: 2, readings: ['Exodus 2']),
    ],
  );

  final today = DateTime(2026, 10, 16);

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    planService = ReadingPlanService(firestore: firestore);
    groupService = GroupService(firestore: firestore);
    paceService = PlanPaceService(firestore: firestore);
    prefsService = UserPreferencesService(firestore: firestore);

    aggregator = ActiveReadingAggregator(
      readingPlanService: planService,
      groupService: groupService,
      paceService: paceService,
      userPreferencesService: prefsService,
      dateProvider: () => today,
      firestore: firestore,
    );

    // Seed test plan documents
    await firestore.collection('custom_plans').doc('p1').set({
      ...testPlan1.toJson(),
      'userId': 'u1',
    });
    await firestore.collection('custom_plans').doc('p2').set({
      ...testPlan2.toJson(),
      'userId': 'u1',
    });
  });

  group('ActiveReadingAggregator - fetch', () {
    test('returns empty snapshot when reader has no plans or groups', () async {
      final snapshot = await aggregator.fetch('u1', today: today);

      expect(snapshot.isEmpty, isTrue);
      expect(snapshot.allReadings, isEmpty);
      expect(snapshot.homeReadings, isEmpty);
      expect(snapshot.activePersonalPlans, isEmpty);
      expect(snapshot.finishedPersonalPlans, isEmpty);
      expect(snapshot.activeGroupReadings, isEmpty);
      expect(snapshot.finishedGroupReadings, isEmpty);
    });

    test('resolves solo personal plans with lifecycle and catch-up status',
        () async {
      // Start p1 today (day 1 due)
      await planService.startPlan('u1', 'p1', startDate: today);

      final snapshot = await aggregator.fetch('u1', today: today);

      expect(snapshot.personalPlans.length, equals(1));
      final item = snapshot.personalPlans.first;
      expect(item.id, equals('p1'));
      expect(item.title, equals('Genesis Plan'));
      expect(item.pinKey, equals('plan:p1'));
      expect(item.isGroup, isFalse);
      expect(item.state, equals(PlanLifecycle.due));
      expect(item.status.total, equals(3));
      expect(item.status.doneCount, equals(0));
      expect(item.currentDay, equals(1));
      expect(item.isCurrentDayCompleted, isFalse);
    });

    test('batches plan document fetches and caches them in memory', () async {
      // Start both plans
      await planService.startPlan('u1', 'p1', startDate: today);
      await planService.startPlan('u1', 'p2', startDate: today);

      final snapshot1 = await aggregator.fetch('u1', today: today);
      expect(snapshot1.personalPlans.length, equals(2));

      // Check cache by fetching directly
      final cachedPlan1 = await aggregator.getPlan('p1', userId: 'u1');
      final cachedPlan2 = await aggregator.getPlan('p2', userId: 'u1');
      expect(cachedPlan1?.title, equals('Genesis Plan'));
      expect(cachedPlan2?.title, equals('Exodus Plan'));

      // Invalidate specific cache entry
      aggregator.invalidateCache(planId: 'p1');
      // Entire cache clear
      aggregator.invalidateCache();
    });

    test('resolves shared group schedule with member completions', () async {
      final groupId = await groupService.createGroup(
        ownerUid: 'owner1',
        name: 'Romans Group',
      );
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc('u1')
          .set({'uid': 'u1', 'role': 'member'});

      final scheduleDate = today;
      await groupService.updateSchedule(
        groupId: groupId,
        schedule: GroupSchedule(date: scheduleDate, chapters: const ['Rom 1']),
      );

      final snapshot = await aggregator.fetch('u1', today: today);

      expect(snapshot.groupReadings.length, equals(1));
      final groupReading = snapshot.groupReadings.first;
      expect(groupReading.id, equals(groupId));
      expect(groupReading.title, equals('Romans Group'));
      expect(groupReading.pinKey, equals('group:$groupId'));
      expect(groupReading.isGroup, isTrue);
      expect(groupReading.state, equals(PlanLifecycle.due));
      expect(groupReading.todaySchedule, isNotNull);
      expect(groupReading.todaySchedule?.chapters, equals(['Rom 1']));
      expect(groupReading.isReadBy('u1'), isFalse);
    });
  });

  group('ActiveReadingsSnapshot - homeReadings ranking & pinning', () {
    test(
        'ranks due -> behind -> ontrack -> wrapup and breaks ties by missedCount',
        () async {
      // Create plans in various lifecycle states:
      // Plan A: ontrack (started today, day 1 already marked)
      await planService.startPlan('u1', 'p1', startDate: today);
      await planService.markDayComplete('u1', 'p1', 1);

      // Plan B: due (started today, day 1 unmarked)
      await planService.startPlan('u1', 'p2', startDate: today);

      final snapshot = await aggregator.fetch('u1', today: today);

      final homeItems = snapshot.homeReadings;
      expect(homeItems.length, equals(2));
      // Plan B (due) ranks before Plan A (ontrack)
      expect(homeItems[0].id, equals('p2'));
      expect(homeItems[0].state, equals(PlanLifecycle.due));
      expect(homeItems[1].id, equals('p1'));
      expect(homeItems[1].state, equals(PlanLifecycle.ontrack));
    });

    test('user pin override hoists pinned reading to index 0', () async {
      // Start both plans
      await planService.startPlan('u1', 'p1', startDate: today); // due
      await planService.startPlan('u1', 'p2', startDate: today); // due

      // Pin p2 via preferences
      await prefsService.updatePreferences(
        'u1',
        const UserPreferences(pinnedReadingId: 'plan:p2'),
      );

      final snapshot = await aggregator.fetch('u1', today: today);

      expect(snapshot.pinnedReadingId, equals('plan:p2'));
      expect(snapshot.homeReadings.first.id, equals('p2'));
      expect(snapshot.homeReadings.first.pinKey, equals('plan:p2'));
    });

    test('excludes complete plans from homeReadings', () async {
      // p2 has 2 days duration; mark both complete
      await planService.startPlan('u1', 'p2', startDate: today);
      await planService.markDayComplete('u1', 'p2', 1);
      await planService.markDayComplete('u1', 'p2', 2);

      final snapshot = await aggregator.fetch('u1', today: today);

      final item = snapshot.personalPlans.firstWhere((p) => p.id == 'p2');
      expect(item.state, equals(PlanLifecycle.complete));
      expect(item.isDone, isTrue);

      // Not shown on Home
      expect(snapshot.homeReadings, isEmpty);

      // In PlansHub: finishedPersonalPlans
      expect(snapshot.finishedPersonalPlans.map((p) => p.id), contains('p2'));
    });

    test('ended plans not yet finished appear as wrapup on Home', () async {
      // Start p1 10 days ago, day 1 read, day 2 and 3 unread -> wrapup
      final pastDate = today.subtract(const Duration(days: 10));
      await planService.startPlan('u1', 'p1', startDate: pastDate);
      await planService.markDayComplete('u1', 'p1', 1);

      final snapshot = await aggregator.fetch('u1', today: today);

      final item = snapshot.personalPlans.first;
      expect(item.state, equals(PlanLifecycle.wrapup));
      expect(item.isDone, isFalse);

      // Shown on Home as wrap-up hero
      expect(snapshot.homeReadings.length, equals(1));
      expect(snapshot.homeReadings.first.state, equals(PlanLifecycle.wrapup));

      // Also in activePersonalPlans on PlansHub
      expect(snapshot.activePersonalPlans.length, equals(1));
    });
  });

  group('ActiveReadingsSnapshot - optimistic mutation helpers', () {
    test('withOptimisticPlanProgress updates progress and recomputes status',
        () async {
      await planService.startPlan('u1', 'p1', startDate: today);
      final initial = await aggregator.fetch('u1', today: today);
      expect(initial.personalPlans.first.state, equals(PlanLifecycle.due));

      final nextProgress =
          initial.personalPlans.first.progress.copyWith(completedDays: [1]);
      final updated = initial.withOptimisticPlanProgress(
        'p1',
        nextProgress,
        today: today,
      );

      expect(
        updated.personalPlans.first.state,
        equals(PlanLifecycle.ontrack),
      );
      expect(updated.personalPlans.first.status.doneCount, equals(1));
    });

    test('withOptimisticGroupCompletion updates member completion', () async {
      final groupId = await groupService.createGroup(
        ownerUid: 'owner1',
        name: 'Group 1',
      );
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc('u1')
          .set({'uid': 'u1', 'role': 'member'});

      final initial = await aggregator.fetch('u1', today: today);
      final updated = initial.withOptimisticGroupCompletion(groupId, 'u1', 1.0);

      expect(updated.groupReadings.first.isReadBy('u1'), isTrue);
    });

    test('withoutReading removes item by id', () async {
      await planService.startPlan('u1', 'p1', startDate: today);
      final initial = await aggregator.fetch('u1', today: today);

      final removed = initial.withoutReading('p1');
      expect(removed.allReadings, isEmpty);
    });
  });

  group('ActiveReadingAggregator - watch', () {
    test('emits initial snapshot and updates when plan is added', () async {
      final stream = aggregator.watch('u1', dateProvider: () => today);

      final snapshots = <ActiveReadingsSnapshot>[];
      final sub = stream.listen(snapshots.add);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(snapshots.length, equals(1));
      expect(snapshots.first.personalPlans, isEmpty);

      // Start a plan
      await planService.startPlan('u1', 'p1', startDate: today);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(snapshots.length, greaterThanOrEqualTo(2));
      expect(snapshots.last.personalPlans.length, equals(1));
      expect(snapshots.last.personalPlans.first.id, equals('p1'));

      await sub.cancel();
    });
  });
}
