import '../models/group_schedule.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';
import 'catch_up_engine.dart';

/// The pace arithmetic behind "Adjust pace" (#810).
///
/// Everything here is pure date/list math over dated readings — the same
/// [GroupSchedule] shape the shared-plan engine consumes — so a personal plan
/// and a member's private overlay for a Shared plan share one implementation.
/// No I/O: callers pass an explicit `today` and already-loaded models, which
/// keeps the three options deterministic and trivially unit-testable.
class PlanPace {
  PlanPace._();

  /// Strips the time component so comparisons are calendar-date based.
  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// `YYYY-MM-DD`, matching the shape `GroupService.dateId` produces (mirrored
  /// here the way `progress_remap.dart` mirrors it, so this file stays free of
  /// the GroupService dependency graph).
  static String dateId(DateTime date) {
    final d = _dateOnly(date);
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  /// A personal plan's readings as dated entries: day `d` lands on
  /// `startDate + (d - 1)` — the same offset math as
  /// [CatchUpEngine.forPersonalPlan] and `getScheduledDay`.
  static List<GroupSchedule> datedPersonalSchedule(
    ReadingPlan plan,
    DateTime startDate,
  ) {
    final start = _dateOnly(startDate);
    return [
      for (final day in plan.schedule)
        GroupSchedule(
          date: DateTime(start.year, start.month, start.day + day.day - 1),
          chapters: day.readings,
        ),
    ];
  }

  /// A personal reader's completion as `YYYY-MM-DD` date ids.
  static Set<String> personalCompletedDateIds(
    ReadingPlan plan,
    UserPlanProgress progress,
  ) {
    final start = _dateOnly(progress.startDate);
    return {
      for (final day in progress.completedDays)
        dateId(DateTime(start.year, start.month, start.day + day - 1)),
    };
  }

  /// How many scheduled days the reader is behind — the same number the plan
  /// card's "N behind" badge shows.
  static int daysBehind(
    List<GroupSchedule> days,
    Set<String> completedDateIds, {
    required DateTime today,
  }) {
    return CatchUpEngine.forGroupSchedule(
      days,
      completedDateIds,
      today: today,
    ).missedCount;
  }

  /// Date of the final scheduled reading, or null when the plan is empty.
  static DateTime? finishOf(List<GroupSchedule> days) {
    if (days.isEmpty) return null;
    var last = days.first.date;
    for (final day in days) {
      if (_dateOnly(day.date).isAfter(_dateOnly(last))) last = day.date;
    }
    return last;
  }

  /// The first day the reader owes a reading: today, unless today's reading
  /// is already done and nothing is behind — then tomorrow.
  static DateTime resumeDate(
    List<GroupSchedule> days,
    Set<String> completedDateIds, {
    required DateTime today,
  }) {
    final t = _dateOnly(today);
    final todayRead = completedDateIds.contains(dateId(t));
    final behind = daysBehind(days, completedDateIds, today: t);
    return todayRead && behind == 0 ? t.add(const Duration(days: 1)) : t;
  }

  /// Stretch: every uncompleted reading slides later by [daysBehind] days.
  ///
  /// Completed days keep their dates, the reading order and per-day loads are
  /// preserved exactly, and the finish moves out by [daysBehind]. Nothing is
  /// marked as missed: the days that were missed simply stop being scheduled.
  static List<GroupSchedule> stretch({
    required List<GroupSchedule> days,
    required Set<String> completedDateIds,
    required int daysBehind,
  }) {
    if (daysBehind <= 0) return List.of(days);
    return [
      for (final day in days)
        completedDateIds.contains(dateId(day.date))
            ? day
            : GroupSchedule(
                date: day.date.add(Duration(days: daysBehind)),
                chapters: day.chapters,
              ),
    ];
  }

  /// Keep the finish: the remaining readings, in order, re-sliced as evenly
  /// as possible across the calendar days from [resumeDate] through
  /// [finishDate].
  ///
  /// A finish date that has already passed is pulled forward to
  /// [resumeDate] — "keeping" a past finish would leave the readings
  /// permanently missed. Days whose even slice is empty become rest days and
  /// are omitted from the schedule, matching how rest days are represented.
  static List<GroupSchedule> redistribute({
    required List<GroupSchedule> days,
    required Set<String> completedDateIds,
    required DateTime resumeDate,
    required DateTime finishDate,
  }) {
    final resume = _dateOnly(resumeDate);
    var finish = _dateOnly(finishDate);
    if (finish.isBefore(resume)) finish = resume;

    final kept = days
        .where((day) => completedDateIds.contains(dateId(day.date)))
        .toList()
      ..sort((a, b) => _dateOnly(a.date).compareTo(_dateOnly(b.date)));

    final remaining = <String>[
      for (final day in days)
        if (!completedDateIds.contains(dateId(day.date))) ...day.chapters,
    ];

    final dayCount = finish.difference(resume).inDays + 1;
    final adjusted = <GroupSchedule>[];
    var cursor = 0;
    for (var i = 0; i < dayCount; i++) {
      // Even split by cumulative position, so a remainder spreads across the
      // span instead of piling onto the first days.
      final end = ((i + 1) * remaining.length) ~/ dayCount;
      final chapters = remaining.sublist(cursor, end);
      cursor = end;
      if (chapters.isEmpty) continue;
      adjusted.add(
        GroupSchedule(
          date: resume.add(Duration(days: i)),
          chapters: chapters,
        ),
      );
    }

    return [...kept, ...adjusted];
  }

  /// Begin again: the same readings in the same order (and with the same gaps
  /// between reading days), re-anchored so the first reading day is
  /// [startDate].
  static List<GroupSchedule> beginAgain({
    required List<GroupSchedule> days,
    required DateTime startDate,
  }) {
    if (days.isEmpty) return const [];
    var first = days.first.date;
    for (final day in days) {
      if (_dateOnly(day.date).isBefore(_dateOnly(first))) first = day.date;
    }
    final start = _dateOnly(startDate);
    final shift = start.difference(_dateOnly(first));
    return [
      for (final day in days)
        GroupSchedule(
          date: day.date.add(shift),
          chapters: day.chapters,
        ),
    ];
  }

  /// Rewrites a personal plan's schedule from adjusted dated readings,
  /// renumbering days from the start date and keeping `durationDays` in step
  /// with the last scheduled day.
  static ReadingPlan withAdjustedSchedule(
    ReadingPlan plan,
    DateTime startDate,
    List<GroupSchedule> adjusted,
  ) {
    final start = _dateOnly(startDate);
    final schedule = [
      for (final day in adjusted)
        ReadingPlanDay(
          day: _dateOnly(day.date).difference(start).inDays + 1,
          readings: day.chapters,
        ),
    ]..sort((a, b) => a.day.compareTo(b.day));
    final lastDay =
        schedule.isEmpty ? plan.durationDays : schedule.last.day;
    return plan.copyWith(schedule: schedule, durationDays: lastDay);
  }
}