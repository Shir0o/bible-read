import '../models/group_plan_config.dart';
import '../models/group_schedule.dart';
import '../models/schedule_mode.dart';
import 'reference_parser.dart';

/// A generated schedule, plus the facts the UI needs to describe it.
class GeneratedPlan {
  /// One entry per reading day, in date order.
  final List<GroupSchedule> days;

  /// How many chapters each day ended up holding. May differ from a hand-set
  /// count when a book boundary or the end of the plan cut it short.
  final List<int> effectiveCounts;

  /// Chapters ahead of the start reference that are not scheduled.
  final int skippedBeforeStart;

  /// Whether generation stopped at [ScheduleGenerator.maxDays] with chapters
  /// still unassigned.
  final bool truncatedAtCap;

  const GeneratedPlan({
    required this.days,
    required this.effectiveCounts,
    required this.skippedBeforeStart,
    required this.truncatedAtCap,
  });

  static const GeneratedPlan empty = GeneratedPlan(
    days: [],
    effectiveCounts: [],
    skippedBeforeStart: 0,
    truncatedAtCap: false,
  );

  /// Total chapters scheduled.
  int get totalChapters {
    var count = 0;
    for (final day in days) {
      count += day.chapters.length;
    }
    return count;
  }

  /// Date of the last reading day, or null when the plan is empty.
  DateTime? get finishesOn => days.isEmpty ? null : days.last.date;
}

class ScheduleGenerator {
  /// Upper bound on generated days. Reading the whole Bible one chapter a day
  /// is 1,189 days; anything beyond this is a misconfiguration rather than a
  /// plan, and is surfaced as [GeneratedPlan.truncatedAtCap] rather than
  /// silently dropping chapters.
  static const int maxDays = 1500;

  /// Generates a schedule from a plan [draft].
  ///
  /// Chapters are laid out in the order the reader added the books — not
  /// canonical Bible order — starting at [GroupPlanDraft.startRef]. Each day
  /// takes its hand-set count if it has one, otherwise whatever the pace calls
  /// for; with [GroupPlanDraft.bookBoundary] set, a day is cut short rather
  /// than allowed to end one book and begin the next.
  static GeneratedPlan planFromDraft(GroupPlanDraft draft) {
    if (draft.books.isEmpty || draft.weekdays.isEmpty) {
      return GeneratedPlan.empty;
    }
    // End-date mode with no date has no pace to derive; generating anyway
    // would drop the whole plan onto day one.
    if (draft.mode == ScheduleMode.endDate && draft.endDate == null) {
      return GeneratedPlan.empty;
    }

    final allChapters = _expandBooks(draft.books);
    if (allChapters.isEmpty) return GeneratedPlan.empty;

    final startIndex = _startIndex(allChapters, draft.startRef);
    final chapters = allChapters.sublist(startIndex);
    if (chapters.isEmpty) return GeneratedPlan.empty;

    // Reading dates are produced as they are needed, so the number of days is
    // an outcome of packing rather than a limit imposed on it.
    var dateCursor = DateTime(
      draft.startDate.year,
      draft.startDate.month,
      draft.startDate.day,
    );
    DateTime nextReadingDate() {
      // draft.weekdays is non-empty here, so a match is at most 6 days away.
      while (!draft.weekdays.contains(dateCursor.weekday)) {
        dateCursor = dateCursor.add(const Duration(days: 1));
      }
      final date = dateCursor;
      dateCursor = dateCursor.add(const Duration(days: 1));
      return date;
    }

    // In end-date mode the pace is whatever finishes the remaining chapters by
    // the requested date. Book boundaries can still push the plan past it — the
    // schedule runs long rather than cramming days the reader did not ask for.
    var remainingTargetDays = 0;
    if (draft.mode == ScheduleMode.endDate && draft.endDate != null) {
      final end = DateTime(
        draft.endDate!.year,
        draft.endDate!.month,
        draft.endDate!.day,
      );
      remainingTargetDays = _countReadingDays(
        draft.startDate,
        end,
        draft.weekdays,
      );
    }

    final days = <GroupSchedule>[];
    final counts = <int>[];
    var cursor = 0;
    var dayIndex = 0;

    while (cursor < chapters.length && dayIndex < maxDays) {
      final remaining = chapters.length - cursor;

      int wanted;
      final override = draft.dayOverrides[dayIndex];
      if (override != null) {
        wanted = override;
      } else if (draft.mode == ScheduleMode.chaptersPerDay) {
        wanted = draft.chaptersPerDay ?? 1;
      } else {
        final daysLeft = remainingTargetDays > 0 ? remainingTargetDays : 1;
        wanted = (remaining / daysLeft).ceil();
      }
      if (wanted < 1) wanted = 1;

      var take = wanted < remaining ? wanted : remaining;

      if (draft.bookBoundary) {
        final book = chapters[cursor].book;
        var run = 0;
        while (run < take && chapters[cursor + run].book == book) {
          run++;
        }
        take = run < 1 ? 1 : run;
      }

      days.add(
        GroupSchedule(
          date: nextReadingDate(),
          chapters: [
            for (var i = cursor; i < cursor + take; i++) chapters[i].reference,
          ],
        ),
      );
      counts.add(take);

      cursor += take;
      dayIndex++;
      if (remainingTargetDays > 0) remainingTargetDays--;
    }

    return GeneratedPlan(
      days: days,
      effectiveCounts: counts,
      skippedBeforeStart: startIndex,
      truncatedAtCap: cursor < chapters.length,
    );
  }

  /// Every chapter of [books], in the order the books were given.
  static List<_Chapter> _expandBooks(List<String> books) {
    final out = <_Chapter>[];
    for (final book in books) {
      final count = ReferenceParser.chapterCount(book) ?? 0;
      for (var i = 1; i <= count; i++) {
        out.add(_Chapter(book, '$book $i'));
      }
    }
    return out;
  }

  /// Index of [startRef] within [chapters]; 0 when it is blank or unmatched, so
  /// a stale reference starts the plan at the beginning rather than emptying it.
  static int _startIndex(List<_Chapter> chapters, String startRef) {
    if (startRef.trim().isEmpty) return 0;
    final target = ReferenceParser.normalizeOne(startRef);
    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i].reference == target) return i;
    }
    return 0;
  }

  /// How many reading days fall between [from] and [to] inclusive.
  static int _countReadingDays(DateTime from, DateTime to, List<int> weekdays) {
    var day = DateTime(from.year, from.month, from.day);
    var count = 0;
    var guard = 0;
    while (!day.isAfter(to) && guard < maxDays * 7 + 7) {
      guard++;
      if (weekdays.contains(day.weekday)) count++;
      day = day.add(const Duration(days: 1));
    }
    return count;
  }

  /// Generates a list of [GroupSchedule] items.
  ///
  /// Retained for callers that have no [GroupPlanDraft]: starts at chapter one
  /// of the first book and lets a day span two books, which is how schedules
  /// were generated before plan configuration was persisted.
  static List<GroupSchedule> generateSchedule({
    required List<String> books,
    required DateTime startDate,
    DateTime? endDate,
    int? fixedChaptersPerDay,
    required List<int> selectedWeekdays,
  }) {
    if (fixedChaptersPerDay == null &&
        (endDate == null || endDate.isBefore(startDate))) {
      return [];
    }

    return planFromDraft(
      GroupPlanDraft(
        books: books,
        startRef: '',
        mode: fixedChaptersPerDay != null
            ? ScheduleMode.chaptersPerDay
            : ScheduleMode.endDate,
        chaptersPerDay: fixedChaptersPerDay,
        startDate: startDate,
        endDate: endDate,
        weekdays: selectedWeekdays,
        bookBoundary: false,
        dayOverrides: const {},
      ),
    ).days;
  }
}

/// A chapter plus the book it belongs to, so the packer can spot book changes
/// without re-parsing the reference string.
class _Chapter {
  final String book;
  final String reference;

  const _Chapter(this.book, this.reference);
}
