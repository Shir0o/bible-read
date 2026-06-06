import '../models/group_schedule.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';

/// Per-reading status, derived from the live completion set (order-independent).
///
/// Ported from the design's `schedule.jsx` (`statusOf`), with `today` renamed to
/// [current] to avoid collision with the daily-habit "today" concept.
enum ReadingStatus {
  /// Read.
  done,

  /// The active reading due now (literally today for daily plans, this week's
  /// passage for a weekly group plan).
  current,

  /// Due earlier than [current] and still unread — the catch-up set.
  missed,

  /// Not yet due.
  upcoming,
}

/// Lifecycle state of a whole plan, ported from the design's `planSummary`
/// (schedule.jsx). The single source of truth for how Home ranks readings and
/// frames the hero.
///
///   • [complete] — every reading read. Truly finished → leaves Home.
///   • [wrapup]   — the calendar window has closed but readings remain. Stays
///                  on Home (quietly) until content-complete; a plan is never
///                  auto-closed just because its dates ran out.
///   • [behind]   — window still open, one or more readings overdue.
///   • [due]      — today is a reading day and today's reading is unread.
///   • [ontrack]  — caught up; nothing outstanding right now.
enum PlanLifecycle { complete, wrapup, behind, due, ontrack }

/// One reading occurrence, normalized across personal and group plans so the
/// engine can compute status without caring which kind of plan produced it.
class ScheduleEntry {
  /// Stable order key — the plan day number (personal) or sorted position (group).
  final int index;

  /// Calendar date this reading is due (date-only; time component ignored).
  final DateTime date;

  /// Chapter references for this reading.
  final List<String> readings;

  /// Whether the user has marked this reading read.
  final bool completed;

  const ScheduleEntry({
    required this.index,
    required this.date,
    required this.readings,
    required this.completed,
  });
}

/// The computed behind/catch-up state for a plan at a given point in time.
class CatchUpStatus {
  /// Input entries, sorted by date ascending.
  final List<ScheduleEntry> entries;

  /// Per-entry status, parallel to [entries].
  final List<ReadingStatus> statuses;

  /// Position of the [ReadingStatus.current] entry in [entries], or -1 when the
  /// whole plan is still in the future.
  final int currentIndex;

  /// Where to resume: first missed, else current, else first upcoming, else -1.
  final int resumeIndex;

  /// Number of entries marked read.
  final int doneCount;

  /// Number of due-but-unread entries — i.e. the "behind" count.
  final int missedCount;

  /// Number of not-yet-due entries.
  final int upcomingCount;

  const CatchUpStatus({
    required this.entries,
    required this.statuses,
    required this.currentIndex,
    required this.resumeIndex,
    required this.doneCount,
    required this.missedCount,
    required this.upcomingCount,
  });

  /// How many readings the user is behind. Synonym for [missedCount].
  int get behindCount => missedCount;

  /// True when nothing is outstanding: no missed readings and the current
  /// reading (if any is due) has been read. Group cards report "in step" on this.
  bool get inStep =>
      missedCount == 0 &&
      (currentIndex < 0 || statuses[currentIndex] == ReadingStatus.done);

  /// The current reading entry, or null when the plan is entirely upcoming.
  ScheduleEntry? get currentEntry =>
      currentIndex < 0 ? null : entries[currentIndex];

  /// Total scheduled readings.
  int get total => entries.length;

  /// Readings still unread.
  int get remaining => entries.length - doneCount;

  /// Calendar date of the final scheduled reading, or null when empty.
  DateTime? get lastDate => entries.isEmpty ? null : entries.last.date;

  /// The reading a returning user should pick up — the current one if any is
  /// due, otherwise the final reading (used to label "Read · <ref>").
  List<String> get currentReadings {
    if (currentIndex >= 0) return entries[currentIndex].readings;
    if (entries.isEmpty) return const [];
    return entries.last.readings;
  }

  /// Derives the [PlanLifecycle] at [today]. Order matters: a plan whose window
  /// has ended but isn't content-complete is [PlanLifecycle.wrapup], never
  /// [PlanLifecycle.behind] — it is never auto-closed by the calendar.
  PlanLifecycle lifecycleAt(DateTime today) {
    final count = entries.length;
    if (count == 0) return PlanLifecycle.ontrack;
    if (doneCount >= count) return PlanLifecycle.complete;
    final last = entries.last.date;
    final lastD = DateTime(last.year, last.month, last.day);
    final todayD = DateTime(today.year, today.month, today.day);
    if (lastD.isBefore(todayD)) return PlanLifecycle.wrapup;
    if (missedCount > 0) return PlanLifecycle.behind;
    if (currentIndex >= 0 &&
        statuses[currentIndex] == ReadingStatus.current) {
      return PlanLifecycle.due;
    }
    return PlanLifecycle.ontrack;
  }
}

/// Pure, cadence-agnostic engine that turns a normalized schedule + completion
/// set into a [CatchUpStatus]. Holds no I/O — callers pass already-loaded models
/// and an explicit `today`, keeping it deterministic and trivially unit-testable.
class CatchUpEngine {
  const CatchUpEngine._();

  /// Strips the time component so comparisons are calendar-date based.
  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// `YYYY-MM-DD` key, matching the format `group_catch_up_page.dart` uses.
  static String dateId(DateTime date) {
    final d = _dateOnly(date);
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  /// Index of the latest entry due on or before [today], or -1 when all entries
  /// are in the future. [entries] must be date-sorted ascending.
  static int _currentIndexOf(List<ScheduleEntry> entries, DateTime today) {
    final t = _dateOnly(today);
    var current = -1;
    for (var i = 0; i < entries.length; i++) {
      if (!_dateOnly(entries[i].date).isAfter(t)) {
        current = i;
      }
    }
    return current;
  }

  /// Status of entry [i] given the current index and completion set.
  static ReadingStatus _statusOf(int i, int current, bool completed) {
    if (completed) return ReadingStatus.done;
    if (i == current) return ReadingStatus.current;
    if (current >= 0 && i < current) return ReadingStatus.missed;
    return ReadingStatus.upcoming;
  }

  /// Core computation over a normalized, date-sorted entry list.
  static CatchUpStatus compute(List<ScheduleEntry> entries,
      {required DateTime today}) {
    final sorted = List<ScheduleEntry>.from(entries)
      ..sort((a, b) => _dateOnly(a.date).compareTo(_dateOnly(b.date)));

    final current = _currentIndexOf(sorted, today);

    final statuses = <ReadingStatus>[];
    var done = 0;
    var missed = 0;
    var upcoming = 0;
    for (var i = 0; i < sorted.length; i++) {
      final status = _statusOf(i, current, sorted[i].completed);
      statuses.add(status);
      switch (status) {
        case ReadingStatus.done:
          done++;
          break;
        case ReadingStatus.missed:
          missed++;
          break;
        case ReadingStatus.upcoming:
          upcoming++;
          break;
        case ReadingStatus.current:
          break;
      }
    }

    // Resume: first missed → else the current reading → else first upcoming.
    var resume = statuses.indexOf(ReadingStatus.missed);
    if (resume < 0) resume = current;
    if (resume < 0) resume = statuses.indexOf(ReadingStatus.upcoming);

    return CatchUpStatus(
      entries: sorted,
      statuses: statuses,
      currentIndex: current,
      resumeIndex: resume,
      doneCount: done,
      missedCount: missed,
      upcomingCount: upcoming,
    );
  }

  /// Builds catch-up state for a personal [ReadingPlan]. Each scheduled day maps
  /// to `startDate + (day - 1)` (the same offset math as
  /// `ReadingPlanService.getScheduledDay`), and completion comes from the
  /// non-sequential `progress.completedDays` set.
  static CatchUpStatus forPersonalPlan(
    ReadingPlan plan,
    UserPlanProgress progress, {
    required DateTime today,
  }) {
    final start = _dateOnly(progress.startDate);
    final completed = progress.completedDays.toSet();
    final entries = plan.schedule
        .map((d) => ScheduleEntry(
              index: d.day,
              date: DateTime(start.year, start.month, start.day + (d.day - 1)),
              readings: d.readings,
              completed: completed.contains(d.day),
            ))
        .toList();
    return compute(entries, today: today);
  }

  /// Builds catch-up state for a group plan from its date-based [schedule].
  /// Group schedules already encode cadence (dates can skip days/weeks), so the
  /// engine's date-based `current` logic handles weekly groups for free.
  /// [completedDateIds] is the set of `YYYY-MM-DD` ids the user has read.
  static CatchUpStatus forGroupSchedule(
    List<GroupSchedule> schedule,
    Set<String> completedDateIds, {
    required DateTime today,
  }) {
    final sorted = List<GroupSchedule>.from(schedule)
      ..sort((a, b) => _dateOnly(a.date).compareTo(_dateOnly(b.date)));
    final entries = <ScheduleEntry>[];
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      entries.add(ScheduleEntry(
        index: i,
        date: s.date,
        readings: s.chapters,
        completed: completedDateIds.contains(dateId(s.date)),
      ));
    }
    return compute(entries, today: today);
  }
}
