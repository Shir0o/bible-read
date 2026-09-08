// The pace arithmetic behind "Adjust pace" for personal Plans (#810).
//
// Fixtures per the epic's Testing Decisions (#790): stretching moves the
// finish by the number of days behind and marks nothing missed; keeping the
// finish redistributes remaining readings across remaining days; beginning
// again resets day one to today while the Showing-up record — which lives
// outside the plan entirely — is untouched by construction; and adjusting a
// member's pace on a Shared plan is expressed as a private overlay, never a
// write to the Group's schedule.
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/models/reading_plan_progress.dart';
import 'package:bible_read/services/catch_up_engine.dart';
import 'package:bible_read/services/plan_pace.dart';

/// A daily plan whose day 1 lands on [start].
ReadingPlan _plan(int days, DateTime start) {
  return ReadingPlan(
    id: 'p1',
    title: 'Test',
    description: '',
    durationDays: days,
    tags: const [],
    schedule: List.generate(
      days,
      (i) => ReadingPlanDay(day: i + 1, readings: ['Gen ${i + 1}']),
    ),
  );
}

UserPlanProgress _progress(DateTime start, List<int> completed) =>
    UserPlanProgress(
      planId: 'p1',
      userId: 'u1',
      startDate: start,
      completedDays: completed,
    );

GroupSchedule _day(DateTime date, List<String> chapters) =>
    GroupSchedule(date: date, chapters: chapters);

String _id(DateTime d) => PlanPace.dateId(d);

void main() {
  // Start Jan 1; today Jan 5; read days 1-2 → days 3-4 missed, day 5 current.
  final start = DateTime(2026, 1, 1);
  final today = DateTime(2026, 1, 5);
  final plan = _plan(7, start);

  group('datedPersonalSchedule / personalCompletedDateIds', () {
    test('day d lands on start + (d - 1), matching the engine', () {
      final days = PlanPace.datedPersonalSchedule(plan, start);
      expect(days.first.date, DateTime(2026, 1, 1));
      expect(days[4].date, DateTime(2026, 1, 5));
      expect(days.last.date, DateTime(2026, 1, 7));
      expect(days.last.chapters, ['Gen 7']);
    });

    test('completion maps day numbers to the same dates', () {
      final ids = PlanPace.personalCompletedDateIds(
        plan,
        _progress(start, [1, 2]),
      );
      expect(ids, {'2026-01-01', '2026-01-02'});
    });

    test('daysBehind agrees with the engine the plan card shows', () {
      final days = PlanPace.datedPersonalSchedule(plan, start);
      final ids = PlanPace.personalCompletedDateIds(
        plan,
        _progress(start, [1, 2]),
      );
      final status = CatchUpEngine.forPersonalPlan(
        plan,
        _progress(start, [1, 2]),
        today: today,
      );
      expect(PlanPace.daysBehind(days, ids, today: today), status.missedCount);
      expect(PlanPace.daysBehind(days, ids, today: today), 2);
    });
  });

  group('stretch', () {
    test('moves the finish out by the days behind', () {
      final days = PlanPace.datedPersonalSchedule(plan, start);
      final ids = PlanPace.personalCompletedDateIds(
        plan,
        _progress(start, [1, 2]),
      );

      final stretched = PlanPace.stretch(
        days: days,
        completedDateIds: ids,
        daysBehind: 2,
      );

      expect(PlanPace.finishOf(stretched), DateTime(2026, 1, 9));
      // Jan 1 - Jan 7 → 2 days behind → finish slides to Jan 9.
    });

    test('marks nothing missed afterwards', () {
      final days = PlanPace.datedPersonalSchedule(plan, start);
      final ids = PlanPace.personalCompletedDateIds(
        plan,
        _progress(start, [1, 2]),
      );

      final stretched = PlanPace.stretch(
        days: days,
        completedDateIds: ids,
        daysBehind: 2,
      );
      final after = CatchUpEngine.forGroupSchedule(
        stretched,
        ids,
        today: today,
      );

      // Day 3's reading now lands on Jan 7 — in the future, not missed.
      expect(after.missedCount, 0);
      expect(after.entries.every((e) => !e.date.isBefore(today) ||
          ids.contains(_id(e.date))), isTrue);
      // Completed days keep their dates, so the ticks stay where they are.
      expect(after.doneCount, 2);
      // Same readings in the same order, nothing dropped or duplicated.
      expect(
        [for (final d in stretched) ...d.chapters],
        [for (final d in days) ...d.chapters],
      );
    });

    test('zero days behind is a no-op', () {
      final days = PlanPace.datedPersonalSchedule(plan, start);
      final stretched = PlanPace.stretch(
        days: days,
        completedDateIds: {},
        daysBehind: 0,
      );
      expect(stretched, days);
    });
  });

  group('redistribute', () {
    test('keeps the finish and spreads remaining readings evenly', () {
      // Read day 1 (Gen 1); behind by 2 on Jan 5; finish is Jan 7.
      final days = PlanPace.datedPersonalSchedule(plan, start);
      final ids = PlanPace.personalCompletedDateIds(
        plan,
        _progress(start, [1]),
      );

      final redistributed = PlanPace.redistribute(
        days: days,
        completedDateIds: ids,
        resumeDate: PlanPace.resumeDate(days, ids, today: today),
        finishDate: PlanPace.finishOf(days)!,
      );

      // The finish date is unchanged.
      expect(PlanPace.finishOf(redistributed), DateTime(2026, 1, 7));
      // Gen 2..7 = 6 remaining readings across Jan 5-7: two per day.
      expect(
        redistributed.where((d) => !ids.contains(_id(d.date))).map((d) => d.chapters),
        [
          ['Gen 2', 'Gen 3'],
          ['Gen 4', 'Gen 5'],
          ['Gen 6', 'Gen 7'],
        ],
      );
      // The completed day keeps its date and its tick.
      expect(redistributed.first.date, DateTime(2026, 1, 1));
      expect(redistributed.first.chapters, ['Gen 1']);
    });

    test('remainder spreads across the span, not onto the first days', () {
      // 5 remaining readings across 2 days → 3 then 2, not 4 then 1.
      final days = [
        _day(DateTime(2026, 1, 1), ['A 1']),
        _day(DateTime(2026, 1, 2), ['A 2']),
        _day(DateTime(2026, 1, 3), ['A 4', 'A 5', 'A 6', 'A 7', 'A 8']),
      ];
      final redistributed = PlanPace.redistribute(
        days: days,
        completedDateIds: {'2026-01-01', '2026-01-02'},
        resumeDate: DateTime(2026, 1, 5),
        finishDate: DateTime(2026, 1, 6),
      );
      // Jan 1-2 stay read; A 4..8 (5 readings) spread across Jan 5-6 →
      // 2 then 3, by cumulative position.
      expect(redistributed.map((d) => d.chapters), [
        ['A 1'],
        ['A 2'],
        ['A 4', 'A 5'],
        ['A 6', 'A 7', 'A 8'],
      ]);
      expect(redistributed.last.date, DateTime(2026, 1, 6));
    });

    test('keeps readings in order across day boundaries', () {
      final days = PlanPace.datedPersonalSchedule(plan, start);
      final ids = PlanPace.personalCompletedDateIds(
        plan,
        _progress(start, [1, 2]),
      );
      final redistributed = PlanPace.redistribute(
        days: days,
        completedDateIds: ids,
        resumeDate: PlanPace.resumeDate(days, ids, today: today),
        finishDate: PlanPace.finishOf(days)!,
      );
      final ordered = [for (final d in redistributed.where(
        (d) => !ids.contains(_id(d.date)),
      )) ...d.chapters];
      expect(ordered, ['Gen 3', 'Gen 4', 'Gen 5', 'Gen 6', 'Gen 7']);
    });

    test('a past finish is pulled forward to the resume date', () {
      final days = PlanPace.datedPersonalSchedule(plan, start);
      final ids = PlanPace.personalCompletedDateIds(
        plan,
        _progress(start, [1, 2]),
      );
      final redistributed = PlanPace.redistribute(
        days: days,
        completedDateIds: ids,
        resumeDate: DateTime(2026, 1, 10),
        finishDate: DateTime(2026, 1, 7), // already past
      );
      expect(PlanPace.finishOf(redistributed), DateTime(2026, 1, 10));
    });
  });

  group('beginAgain', () {
    test('resets day one to today, preserving the reading sequence', () {
      final days = PlanPace.datedPersonalSchedule(plan, start);

      final restarted = PlanPace.beginAgain(
        days: days,
        startDate: DateTime(2026, 3, 15),
      );

      expect(restarted.first.date, DateTime(2026, 3, 15));
      expect(restarted.last.date, DateTime(2026, 3, 21));
      // Same readings, same order — the Showing-up record lives in the
      // per-user `reading` collection and per-Group feeds, outside the plan,
      // so resetting the plan cannot touch it by construction.
      expect(
        [for (final d in restarted) ...d.chapters],
        [for (final d in days) ...d.chapters],
      );
    });

    test('preserves gaps between reading days (weekly cadence)', () {
      // Mondays only: Jan 5 and Jan 12 are reading days.
      final mondays = [
        _day(DateTime(2026, 1, 5), ['A 1']),
        _day(DateTime(2026, 1, 12), ['A 2']),
      ];
      final restarted = PlanPace.beginAgain(
        days: mondays,
        startDate: DateTime(2026, 2, 2), // a Monday
      );
      expect(restarted.map((d) => d.date), [
        DateTime(2026, 2, 2),
        DateTime(2026, 2, 9),
      ]);
    });
  });

  group('withAdjustedSchedule', () {
    test('renumbers days from the start and keeps durationDays in step', () {
      final days = PlanPace.datedPersonalSchedule(plan, start);
      final stretched = PlanPace.stretch(
        days: days,
        completedDateIds: {},
        daysBehind: 2,
      );
      final updated = PlanPace.withAdjustedSchedule(plan, start, stretched);
      // Nothing completed, so stretch shifted day one from Jan 1 to Jan 3 —
      // renumbered from the Jan 1 anchor that is day 3.
      expect(updated.schedule.first.day, 3);
      expect(updated.schedule.last.day, 9);
      expect(updated.durationDays, 9);
      expect(updated.schedule.map((d) => d.readings),
          plan.schedule.map((d) => d.readings));
    });
  });
}