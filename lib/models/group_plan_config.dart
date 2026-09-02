import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/reference_parser.dart';
import 'group_schedule.dart';
import 'schedule_mode.dart';

/// The configuration a group's reading schedule is generated from.
///
/// Persisted on the group document as `planConfig` so editing a plan is
/// lossless. Without it the only record of a plan is the materialised schedule,
/// from which the starting chapter and any hand-set day lengths cannot be
/// recovered — reopening the edit screen would silently reset a plan that
/// starts at Jeremiah 1 back to Isaiah 1.
class GroupPlanDraft {
  /// Schema version of the persisted map, so later changes can migrate.
  static const int schemaVersion = 1;

  /// Books to read, in the order the reader added them. Reading order follows
  /// this list, not canonical Bible order.
  final List<String> books;

  /// Chapter day one begins with, e.g. `'Jeremiah 1'`. Everything in [books]
  /// ahead of it is left out of the plan.
  final String startRef;

  /// Whether the pace is driven by a chapter count or by a finish date.
  final ScheduleMode mode;

  /// Chapters per reading day. Null in [ScheduleMode.endDate].
  final int? chaptersPerDay;

  /// First reading day.
  final DateTime startDate;

  /// Requested finish date. Null in [ScheduleMode.chaptersPerDay].
  final DateTime? endDate;

  /// Weekdays that carry a reading, using [DateTime.weekday] (Mon = 1).
  final List<int> weekdays;

  /// Whether a day may never end one book and begin the next.
  final bool bookBoundary;

  /// Hand-set chapter counts by day index. A day absent from this map takes
  /// whatever the pace calls for.
  final Map<int, int> dayOverrides;

  /// Bumped on every regeneration, so members can tell their cached progress
  /// predates the current schedule.
  final int revision;

  const GroupPlanDraft({
    required this.books,
    required this.startRef,
    required this.mode,
    required this.chaptersPerDay,
    required this.startDate,
    required this.endDate,
    required this.weekdays,
    required this.bookBoundary,
    required this.dayOverrides,
    this.revision = 0,
  });

  /// An empty plan starting today, two chapters a day, every day, with books
  /// kept on their own days.
  factory GroupPlanDraft.initial({DateTime? startDate}) {
    final now = startDate ?? DateTime.now();
    return GroupPlanDraft(
      books: const [],
      startRef: '',
      mode: ScheduleMode.chaptersPerDay,
      chaptersPerDay: 2,
      startDate: DateTime(now.year, now.month, now.day),
      endDate: null,
      weekdays: const [1, 2, 3, 4, 5, 6, 7],
      bookBoundary: true,
      dayOverrides: const {},
    );
  }

  GroupPlanDraft copyWith({
    List<String>? books,
    String? startRef,
    ScheduleMode? mode,
    int? chaptersPerDay,
    bool clearChaptersPerDay = false,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    List<int>? weekdays,
    bool? bookBoundary,
    Map<int, int>? dayOverrides,
    int? revision,
  }) {
    return GroupPlanDraft(
      books: books ?? this.books,
      startRef: startRef ?? this.startRef,
      mode: mode ?? this.mode,
      chaptersPerDay:
          clearChaptersPerDay ? null : (chaptersPerDay ?? this.chaptersPerDay),
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      weekdays: weekdays ?? this.weekdays,
      bookBoundary: bookBoundary ?? this.bookBoundary,
      dayOverrides: dayOverrides ?? this.dayOverrides,
      revision: revision ?? this.revision,
    );
  }

  /// Serializes this draft for the group document's `planConfig` field.
  ///
  /// Day-override keys are written as strings because Firestore map keys are
  /// always strings.
  Map<String, dynamic> toFirestore() => {
        'version': schemaVersion,
        'books': books,
        'startRef': startRef,
        'mode': mode.name,
        'chaptersPerDay': chaptersPerDay,
        'startDate': Timestamp.fromDate(
          DateTime.utc(startDate.year, startDate.month, startDate.day),
        ),
        'endDate': endDate == null
            ? null
            : Timestamp.fromDate(
                DateTime.utc(endDate!.year, endDate!.month, endDate!.day),
              ),
        'weekdays': weekdays,
        'bookBoundary': bookBoundary,
        'dayOverrides': dayOverrides.map((k, v) => MapEntry(k.toString(), v)),
        'revision': revision,
      };

  /// Reads a draft from a group document's `planConfig` field.
  ///
  /// A null or unreadable map yields [GroupPlanDraft.initial], so a group saved
  /// before this field existed is not a special case for callers.
  factory GroupPlanDraft.fromMap(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return GroupPlanDraft.initial();

    final books =
        (data['books'] as List?)?.whereType<String>().toList() ?? <String>[];
    final weekdays = (data['weekdays'] as List?)
        ?.whereType<num>()
        .map((n) => n.toInt())
        .toList();
    final overrides = <int, int>{};
    final rawOverrides = data['dayOverrides'];
    if (rawOverrides is Map) {
      rawOverrides.forEach((key, value) {
        final index = int.tryParse('$key');
        final count = value is num ? value.toInt() : null;
        if (index != null && count != null) overrides[index] = count;
      });
    }

    return GroupPlanDraft(
      books: books,
      startRef: data['startRef'] as String? ?? '',
      mode: data['mode'] == ScheduleMode.chaptersPerDay.name
          ? ScheduleMode.chaptersPerDay
          : ScheduleMode.endDate,
      chaptersPerDay: (data['chaptersPerDay'] as num?)?.toInt(),
      startDate: _toLocalDate(data['startDate']) ?? DateTime.now(),
      endDate: _toLocalDate(data['endDate']),
      weekdays: (weekdays == null || weekdays.isEmpty)
          ? const [1, 2, 3, 4, 5, 6, 7]
          : weekdays,
      bookBoundary: data['bookBoundary'] as bool? ?? false,
      dayOverrides: overrides,
      revision: (data['revision'] as num?)?.toInt() ?? 0,
    );
  }

  /// Reconstructs a draft from an already-materialised schedule, for groups
  /// created before `planConfig` was persisted.
  ///
  /// Recovers the piece the edit screen used to lose — the starting chapter, in
  /// `schedule.first.chapters.first`. [bookBoundary] and [dayOverrides] are
  /// deliberately *not* inferred: a legacy schedule was generated without them,
  /// so assuming them would reshape a plan nobody asked to reshape.
  factory GroupPlanDraft.inferFromSchedule(List<GroupSchedule> schedule) {
    if (schedule.isEmpty) return GroupPlanDraft.initial();

    final books = <String>[];
    for (final day in schedule) {
      for (final chapter in day.chapters) {
        final book = ReferenceParser.parseBook(chapter);
        if (book != null && !books.contains(book)) books.add(book);
      }
    }

    final weekdays =
        <int>{for (final day in schedule) day.date.weekday}.toList()..sort();

    final firstChapters = schedule.first.chapters;

    return GroupPlanDraft(
      books: books,
      startRef: firstChapters.isEmpty
          ? ''
          : ReferenceParser.normalizeOne(firstChapters.first),
      mode: ScheduleMode.endDate,
      chaptersPerDay: null,
      startDate: schedule.first.date,
      endDate: schedule.last.date,
      weekdays: weekdays.isEmpty ? const [1, 2, 3, 4, 5, 6, 7] : weekdays,
      bookBoundary: false,
      dayOverrides: const {},
    );
  }

  /// Reads a stored date back as a calendar day.
  ///
  /// Dates are written at UTC midnight, so the components must be read in UTC
  /// too — converting to local time first lands on the previous day for every
  /// reader west of Greenwich.
  static DateTime? _toLocalDate(Object? value) {
    if (value is Timestamp) {
      final d = value.toDate().toUtc();
      return DateTime(d.year, d.month, d.day);
    }
    // A raw DateTime already carries the calendar day in its own components.
    if (value is DateTime) return DateTime(value.year, value.month, value.day);
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupPlanDraft &&
          _listEq(other.books, books) &&
          other.startRef == startRef &&
          other.mode == mode &&
          other.chaptersPerDay == chaptersPerDay &&
          other.startDate == startDate &&
          other.endDate == endDate &&
          _listEq(other.weekdays, weekdays) &&
          other.bookBoundary == bookBoundary &&
          _mapEq(other.dayOverrides, dayOverrides) &&
          other.revision == revision;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(books),
        startRef,
        mode,
        chaptersPerDay,
        startDate,
        endDate,
        Object.hashAll(weekdays),
        bookBoundary,
        Object.hashAll(
            dayOverrides.entries.map((e) => Object.hash(e.key, e.value))),
        revision,
      );

  static bool _listEq<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _mapEq(Map<int, int> a, Map<int, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
