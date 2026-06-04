import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/models/reading_plan_progress.dart';
import 'package:bible_read/services/catch_up_engine.dart';
import 'package:flutter_test/flutter_test.dart';

ReadingPlan _dailyPlan(int days) {
  return ReadingPlan(
    id: 'p1',
    title: 'Test',
    description: '',
    durationDays: days,
    tags: const [],
    schedule: List.generate(
      days,
      (i) => ReadingPlanDay(day: i + 1, readings: ['Reading ${i + 1}']),
    ),
  );
}

UserPlanProgress _progress({
  required DateTime startDate,
  required List<int> completedDays,
}) {
  return UserPlanProgress(
    planId: 'p1',
    userId: 'u1',
    startDate: startDate,
    completedDays: completedDays,
  );
}

void main() {
  group('CatchUpEngine.dateId', () {
    test('formats as zero-padded YYYY-MM-DD, date-only', () {
      expect(
        CatchUpEngine.dateId(DateTime(2026, 1, 9, 23, 59)),
        '2026-01-09',
      );
    });
  });

  group('forPersonalPlan — daily cadence', () {
    // Start Jan 1; today is Jan 5 → days 1..5 are due, days 6+ upcoming.
    final start = DateTime(2026, 1, 1);
    final today = DateTime(2026, 1, 5);
    final plan = _dailyPlan(7);

    test('seeded completion yields correct status breakdown + behind count', () {
      // Read days 1-2; missed 3-4; today is day 5; 6-7 upcoming.
      final status = CatchUpEngine.forPersonalPlan(
        plan,
        _progress(startDate: start, completedDays: [1, 2]),
        today: today,
      );

      expect(status.statuses, [
        ReadingStatus.done, // day 1
        ReadingStatus.done, // day 2
        ReadingStatus.missed, // day 3
        ReadingStatus.missed, // day 4
        ReadingStatus.current, // day 5 (today)
        ReadingStatus.upcoming, // day 6
        ReadingStatus.upcoming, // day 7
      ]);
      expect(status.doneCount, 2);
      expect(status.missedCount, 2);
      expect(status.behindCount, 2);
      expect(status.upcomingCount, 2);
      expect(status.currentIndex, 4);
      expect(status.currentEntry!.index, 5);
      expect(status.resumeIndex, 2); // first missed = day 3 at position 2
      expect(status.inStep, isFalse);
    });

    test('order-independent: completing a later day still flags earlier misses',
        () {
      // Read day 5 (current) but not 3/4 → still behind by 2, resume at first miss.
      final status = CatchUpEngine.forPersonalPlan(
        plan,
        _progress(startDate: start, completedDays: [1, 2, 5]),
        today: today,
      );
      expect(status.statuses[4], ReadingStatus.done); // day 5 read
      expect(status.statuses[2], ReadingStatus.missed); // day 3 still missed
      expect(status.statuses[3], ReadingStatus.missed); // day 4 still missed
      expect(status.behindCount, 2);
      expect(status.currentIndex, 4);
      expect(status.resumeIndex, 2);
      expect(status.inStep, isFalse); // current done but misses remain
    });

    test('in step when current read and nothing missed', () {
      final status = CatchUpEngine.forPersonalPlan(
        plan,
        _progress(startDate: start, completedDays: [1, 2, 3, 4, 5]),
        today: today,
      );
      expect(status.behindCount, 0);
      expect(status.inStep, isTrue);
      expect(status.statuses[5], ReadingStatus.upcoming);
    });

    test('fully completed plan is in step with no upcoming', () {
      final status = CatchUpEngine.forPersonalPlan(
        plan,
        _progress(startDate: start, completedDays: [1, 2, 3, 4, 5, 6, 7]),
        today: DateTime(2026, 1, 20),
      );
      expect(status.doneCount, 7);
      expect(status.missedCount, 0);
      expect(status.upcomingCount, 0);
      expect(status.inStep, isTrue);
    });
  });

  group('forPersonalPlan — edge cases', () {
    test('today before start: all upcoming, no current', () {
      final plan = _dailyPlan(3);
      final status = CatchUpEngine.forPersonalPlan(
        plan,
        _progress(startDate: DateTime(2026, 6, 1), completedDays: []),
        today: DateTime(2026, 5, 30),
      );
      expect(status.currentIndex, -1);
      expect(status.statuses.every((s) => s == ReadingStatus.upcoming), isTrue);
      expect(status.behindCount, 0);
      expect(status.resumeIndex, 0); // first upcoming
      expect(status.inStep, isTrue); // nothing due yet
    });

    test('empty schedule', () {
      final plan = ReadingPlan(
        id: 'p',
        title: 't',
        description: '',
        durationDays: 0,
        tags: const [],
        schedule: const [],
      );
      final status = CatchUpEngine.forPersonalPlan(
        plan,
        _progress(startDate: DateTime(2026, 1, 1), completedDays: []),
        today: DateTime(2026, 1, 5),
      );
      expect(status.entries, isEmpty);
      expect(status.currentIndex, -1);
      expect(status.resumeIndex, -1);
      expect(status.inStep, isTrue);
    });
  });

  group('forGroupSchedule — weekly/date-based cadence', () {
    // Weekly group: readings on Jan 6, 13, 20, 27. Today Jan 16 → current is
    // Jan 13's passage (this week), NOT literally today's date.
    final schedule = [
      GroupSchedule(date: DateTime(2026, 1, 6), chapters: const ['John 1']),
      GroupSchedule(date: DateTime(2026, 1, 13), chapters: const ['John 2']),
      GroupSchedule(date: DateTime(2026, 1, 20), chapters: const ['John 3']),
      GroupSchedule(date: DateTime(2026, 1, 27), chapters: const ['John 4']),
    ];

    test('current is the latest passage due on/before today, gaps respected', () {
      final status = CatchUpEngine.forGroupSchedule(
        schedule,
        {'2026-01-06'}, // read week 1 only
        today: DateTime(2026, 1, 16),
      );
      expect(status.currentIndex, 1); // Jan 13 passage
      expect(status.currentEntry!.readings, ['John 2']);
      expect(status.statuses, [
        ReadingStatus.done, // Jan 6 read
        ReadingStatus.current, // Jan 13 this week
        ReadingStatus.upcoming, // Jan 20
        ReadingStatus.upcoming, // Jan 27
      ]);
      expect(status.behindCount, 0); // nothing missed, current just unread
      expect(status.inStep, isFalse); // current week unread
    });

    test('missed earlier week reports behind', () {
      final status = CatchUpEngine.forGroupSchedule(
        schedule,
        {}, // read nothing
        today: DateTime(2026, 1, 16),
      );
      expect(status.statuses[0], ReadingStatus.missed); // Jan 6 unread + past
      expect(status.statuses[1], ReadingStatus.current); // Jan 13
      expect(status.behindCount, 1);
      expect(status.resumeIndex, 0);
    });

    test('unsorted input is sorted by date before computing', () {
      final shuffled = [schedule[2], schedule[0], schedule[3], schedule[1]];
      final status = CatchUpEngine.forGroupSchedule(
        shuffled,
        {'2026-01-06', '2026-01-13'},
        today: DateTime(2026, 1, 16),
      );
      expect(
        status.entries.map((e) => e.date).toList(),
        [
          DateTime(2026, 1, 6),
          DateTime(2026, 1, 13),
          DateTime(2026, 1, 20),
          DateTime(2026, 1, 27),
        ],
      );
      expect(status.inStep, isTrue); // both due weeks read
    });
  });
}
