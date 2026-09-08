// Persistence fixtures for "Adjust pace" (#810): what actually lands in
// Firestore.
//
//   - a personal schedule adjustment rewrites the plan in place, so the
//     document id and the reader's plan_progress survive;
//   - begin-again resets day one to today and drops completed day numbers,
//     but the Showing-up record (users/{uid}/reading) is never touched;
//   - a Shared-plan adjustment writes only the reader's own
//     users/{uid}/plan_pace/{groupId} overlay — the Group's schedule and the
//     other members' progress are untouched by construction.
import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/models/reading_plan_progress.dart';
import 'package:bible_read/services/plan_pace.dart';
import 'package:bible_read/services/plan_pace_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

ReadingPlan _plan({DateTime? start}) {
  return ReadingPlan(
    id: 'p1',
    title: 'Morning Light',
    description: '',
    durationDays: 3,
    tags: const [],
    schedule: const [
      ReadingPlanDay(day: 1, readings: ['Gen 1']),
      ReadingPlanDay(day: 2, readings: ['Gen 2']),
      ReadingPlanDay(day: 3, readings: ['Gen 3']),
    ],
    config: start == null
        ? null
        : {'startDate': start.toIso8601String()},
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late PlanPaceService paceService;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    paceService = PlanPaceService(firestore: firestore);
  });

  group('applyPersonalSchedule', () {
    test('rewrites the plan in place, keeping its document id', () async {
      final plan = _plan();
      await firestore.collection('custom_plans').doc('p1').set({
        ...plan.toJson(),
        'userId': 'u1',
      });

      final start = DateTime(2026, 1, 1);
      final days = PlanPace.datedPersonalSchedule(plan, start);
      await paceService.applyPersonalSchedule(
        uid: 'u1',
        plan: plan,
        startDate: start,
        adjusted: PlanPace.stretch(
          days: days,
          completedDateIds: {'2026-01-01'},
          daysBehind: 2,
        ),
      );

      // Same document — no duplicate plan was created.
      final plans = await firestore.collection('custom_plans').get();
      expect(plans.docs, hasLength(1));
      expect(plans.docs.single.id, 'p1');

      final updated = ReadingPlan.fromJson({
        ...plans.docs.single.data(),
        'id': plans.docs.single.id,
      });
      // Finish moved out by 2 (Jan 3 → Jan 5); the schedule was renumbered.
      expect(updated.schedule.last.day, 5);
      expect(updated.durationDays, 5);
      // userId is preserved via the merge, so the plan is still findable.
      expect(plans.docs.single.data()['userId'], 'u1');
    });
  });

  group('beginPersonalPlanAgain', () {
    test('resets day one to today and preserves the Showing-up record',
        () async {
      final plan = _plan();
      final start = DateTime(2026, 1, 1);
      await firestore.collection('custom_plans').doc('p1').set({
        ...plan.toJson(),
        'userId': 'u1',
      });

      // The reader read day 1 on Jan 1 and that day counted as showing up:
      // the habit record lives at users/{uid}/reading/{date}.
      await firestore
          .collection('users')
          .doc('u1')
          .collection('plan_progress')
          .doc('p1')
          .set(
            UserPlanProgress(
              planId: 'p1',
              userId: 'u1',
              startDate: start,
              completedDays: [1],
            ).toFirestore(),
          );
      await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc('2026-01-01')
          .set({'read': true});

      final today = DateTime(2026, 3, 15);
      await paceService.beginPersonalPlanAgain(
        uid: 'u1',
        plan: plan,
        startDate: today,
        progress: UserPlanProgress(
          planId: 'p1',
          userId: 'u1',
          startDate: start,
          completedDays: [1],
        ),
      );

      // Day one is today again: progress re-anchored, completed days gone.
      final progress = UserPlanProgress.fromFirestore(
        await firestore
            .collection('users')
            .doc('u1')
            .collection('plan_progress')
            .doc('p1')
            .get(),
      );
      expect(progress.startDate, today);
      expect(progress.completedDays, isEmpty);

      final plans = await firestore.collection('custom_plans').get();
      final updated = ReadingPlan.fromJson({
        ...plans.docs.single.data(),
        'id': plans.docs.single.id,
      });
      expect(updated.schedule.first.day, 1);

      // The Showing-up record survives — begin again never touches it.
      final habit = await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc('2026-01-01')
          .get();
      expect(habit.exists, isTrue);
      expect(habit.data()?['read'], isTrue);
    });

    test('creates progress when none exists', () async {
      final plan = _plan();
      await firestore.collection('custom_plans').doc('p1').set({
        ...plan.toJson(),
        'userId': 'u1',
      });

      final today = DateTime(2026, 3, 15);
      await paceService.beginPersonalPlanAgain(
        uid: 'u1',
        plan: plan,
        startDate: today,
        progress: UserPlanProgress(
          planId: 'p1',
          userId: 'u1',
          startDate: DateTime(2026, 1, 1),
          completedDays: const [],
        ),
      );

      final progress = await firestore
          .collection('users')
          .doc('u1')
          .collection('plan_progress')
          .doc('p1')
          .get();
      expect(progress.exists, isTrue);
      expect(progress.data()?['completedDays'], isEmpty);
    });
  });

  group('applySharedPlanOverlay', () {
    test('writes only the adjusting reader\'s overlay — the group schedule '
        'and other members\' progress are untouched', () async {
      // The Group's schedule, shared by every member.
      final groupSchedule = [
        {'chapters': ['Gen 1'], 'date': DateTime(2026, 1, 1)},
        {'chapters': ['Gen 2'], 'date': DateTime(2026, 1, 2)},
      ];
      final groupRef = firestore.collection('groups').doc('g1');
      for (final day in groupSchedule) {
        await groupRef.collection('schedule').doc('2026-01-0'
            '${groupSchedule.indexOf(day) + 1}').set(day);
      }
      // Another member has progress.
      await groupRef
          .collection('progress')
          .doc('2026-01-01')
          .collection('entries')
          .doc('u2')
          .set({'count': 1, 'done': true, 'uid': 'u2', 'groupId': 'g1'});

      final List<GroupSchedule> adjusted = [
        GroupSchedule(
          date: DateTime(2026, 1, 5),
          chapters: const ['Gen 1'],
        ),
        GroupSchedule(
          date: DateTime(2026, 1, 6),
          chapters: const ['Gen 2'],
        ),
      ];
      await paceService.applySharedPlanOverlay(
        uid: 'u1',
        groupId: 'g1',
        adjusted: adjusted,
      );

      // The overlay exists for the adjusting reader only, at their own path.
      final overlay = await firestore
          .collection('users')
          .doc('u1')
          .collection('plan_pace')
          .doc('g1')
          .get();
      expect(overlay.exists, isTrue);
      final stored = overlay.data()?['days'] as List;
      expect(stored, hasLength(2));
      expect((stored.first['chapters'] as List), ['Gen 1']);
      expect(stored.first['date'], '2026-01-05');
      expect(stored.last['date'], '2026-01-06');

      // The Group's schedule is exactly as it was.
      final schedule = await groupRef.collection('schedule').get();
      expect(schedule.docs.map((d) => d.id).toSet(), {'2026-01-01', '2026-01-02'});
      expect(
        schedule.docs.map((d) => (d.data()['date'] as dynamic).toDate()),
        everyElement(anyOf(DateTime(2026, 1, 1), DateTime(2026, 1, 2))),
      );

      // The other member's progress is exactly as it was.
      final other = await groupRef
          .collection('progress')
          .doc('2026-01-01')
          .collection('entries')
          .doc('u2')
          .get();
      expect(other.exists, isTrue);
      expect(other.data()?['count'], 1);

      // No overlay was written for the other member.
      expect(
        (await firestore
                .collection('users')
                .doc('u2')
                .collection('plan_pace')
                .get())
            .docs,
        isEmpty,
      );
    });

    test('overlay round-trips through sharedPlanOverlay', () async {
      final List<GroupSchedule> adjusted = [
        GroupSchedule(
          date: DateTime(2026, 1, 5),
          chapters: const ['Gen 1', 'Gen 2'],
        ),
      ];
      await paceService.applySharedPlanOverlay(
        uid: 'u1',
        groupId: 'g1',
        adjusted: adjusted,
      );

      final loaded = await paceService.sharedPlanOverlay('u1', 'g1').first;
      expect(loaded, hasLength(1));
      expect(loaded!.single.date, DateTime(2026, 1, 5));
      expect(loaded.single.chapters, ['Gen 1', 'Gen 2']);
    });

    test('sharedPlanOverlay is null when none stored', () async {
      expect(await paceService.sharedPlanOverlay('u1', 'g1').first, isNull);
    });

    test('clearSharedPlanOverlay removes it', () async {
      await paceService.applySharedPlanOverlay(
        uid: 'u1',
        groupId: 'g1',
        adjusted: [
          GroupSchedule(
            date: DateTime(2026, 1, 5),
            chapters: const ['Gen 1'],
          ),
        ],
      );
      await paceService.clearSharedPlanOverlay(uid: 'u1', groupId: 'g1');
      expect(await paceService.sharedPlanOverlay('u1', 'g1').first, isNull);
    });
  });
}