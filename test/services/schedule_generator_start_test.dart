// Covers starting a plan partway in, keeping books off each other's days, and
// hand-setting how much an individual day holds.
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group_plan_config.dart';
import 'package:bible_read/models/schedule_mode.dart';
import 'package:bible_read/services/reference_parser.dart';
import 'package:bible_read/services/schedule_generator.dart';

GroupPlanDraft _draft({
  required List<String> books,
  required String startRef,
  int? chaptersPerDay = 2,
  DateTime? endDate,
  bool bookBoundary = true,
  Map<int, int> dayOverrides = const {},
  List<int> weekdays = const [1, 2, 3, 4, 5, 6, 7],
}) {
  return GroupPlanDraft(
    books: books,
    startRef: startRef,
    mode: endDate == null ? ScheduleMode.chaptersPerDay : ScheduleMode.endDate,
    chaptersPerDay: chaptersPerDay,
    startDate: DateTime(2026, 9, 1),
    endDate: endDate,
    weekdays: weekdays,
    bookBoundary: bookBoundary,
    dayOverrides: dayOverrides,
  );
}

List<String> _allChapters(List<dynamic> days) =>
    [for (final d in days) ...d.chapters as List<String>];

void main() {
  group('starting chapter', () {
    test('the reported case: day one is Jeremiah 1, day two Jeremiah 2-3', () {
      final plan = ScheduleGenerator.planFromDraft(
        _draft(
          books: ['Isaiah', 'Jeremiah'],
          startRef: 'Jeremiah 1',
          dayOverrides: {0: 1, 1: 2},
        ),
      );

      expect(plan.days[0].chapters, ['Jeremiah 1']);
      expect(plan.days[1].chapters, ['Jeremiah 2', 'Jeremiah 3']);
      expect(plan.skippedBeforeStart, 66);
      expect(_allChapters(plan.days).length, 52);
      expect(_allChapters(plan.days).first, 'Jeremiah 1');
      expect(_allChapters(plan.days).last, 'Jeremiah 52');
    });

    test('skips books by selection order, not canonical order', () {
      // Revelation is read first because it was added first, so starting at
      // Genesis 1 drops it. Canonical order would drop Genesis instead.
      final plan = ScheduleGenerator.planFromDraft(
        _draft(books: ['Revelation', 'Genesis'], startRef: 'Genesis 1'),
      );

      expect(plan.skippedBeforeStart, 22);
      expect(plan.days.first.chapters.first, 'Genesis 1');
      expect(_allChapters(plan.days).any((c) => c.startsWith('Revelation')),
          isFalse);
      expect(_allChapters(plan.days).length, 50);
    });

    test('starting at the last chapter leaves a single day', () {
      final plan = ScheduleGenerator.planFromDraft(
        _draft(books: ['Jude', 'Obadiah'], startRef: 'Obadiah 1'),
      );

      expect(plan.days, hasLength(1));
      expect(plan.days.single.chapters, ['Obadiah 1']);
      expect(plan.skippedBeforeStart, 1);
    });

    test('an unknown start reference falls back to the beginning', () {
      final plan = ScheduleGenerator.planFromDraft(
        _draft(books: ['Jude'], startRef: 'Habakkuk 2'),
      );

      expect(plan.skippedBeforeStart, 0);
      expect(plan.days.first.chapters.first, 'Jude 1');
    });

    test('an empty start reference starts at the beginning', () {
      final plan = ScheduleGenerator.planFromDraft(
        _draft(books: ['Obadiah', 'Jude'], startRef: ''),
      );

      expect(plan.skippedBeforeStart, 0);
      expect(_allChapters(plan.days), ['Obadiah 1', 'Jude 1']);
    });
  });

  group('book boundaries', () {
    test('a day never ends one book and begins the next', () {
      final plan = ScheduleGenerator.planFromDraft(
        _draft(
          books: ['Jude', 'Philemon', 'Obadiah'],
          startRef: 'Jude 1',
          chaptersPerDay: 5,
        ),
      );

      expect(plan.days, hasLength(3));
      expect(plan.days[0].chapters, ['Jude 1']);
      expect(plan.days[1].chapters, ['Philemon 1']);
      expect(plan.days[2].chapters, ['Obadiah 1']);
    });

    test('turning it off lets a day straddle two books', () {
      final plan = ScheduleGenerator.planFromDraft(
        _draft(
          books: ['Jude', 'Philemon'],
          startRef: 'Jude 1',
          bookBoundary: false,
        ),
      );

      expect(plan.days, hasLength(1));
      expect(plan.days.single.chapters, ['Jude 1', 'Philemon 1']);
    });

    test('truncates the last day of a book rather than merging', () {
      // Obadiah has 1 chapter; at 2 a day the Jonah run must start fresh.
      final plan = ScheduleGenerator.planFromDraft(
        _draft(books: ['Obadiah', 'Jonah'], startRef: 'Obadiah 1'),
      );

      expect(plan.days[0].chapters, ['Obadiah 1']);
      expect(plan.days[1].chapters, ['Jonah 1', 'Jonah 2']);
      expect(plan.days[2].chapters, ['Jonah 3', 'Jonah 4']);
    });
  });

  group('hand-set days', () {
    test('an override longer than the book is clamped by the boundary', () {
      final plan = ScheduleGenerator.planFromDraft(
        _draft(
          books: ['Obadiah', 'Jonah'],
          startRef: 'Obadiah 1',
          dayOverrides: {0: 5},
        ),
      );

      expect(plan.days[0].chapters, ['Obadiah 1']);
      expect(plan.effectiveCounts[0], 1);
    });

    test('an override longer than the remaining chapters is clamped', () {
      final plan = ScheduleGenerator.planFromDraft(
        _draft(
          books: ['Jonah'],
          startRef: 'Jonah 3',
          dayOverrides: {0: 9},
        ),
      );

      expect(plan.days.single.chapters, ['Jonah 3', 'Jonah 4']);
      expect(plan.effectiveCounts, [2]);
    });

    test('later days shift when an earlier day is shortened', () {
      final even = ScheduleGenerator.planFromDraft(
        _draft(books: ['Jeremiah'], startRef: 'Jeremiah 1'),
      );
      final shifted = ScheduleGenerator.planFromDraft(
        _draft(
          books: ['Jeremiah'],
          startRef: 'Jeremiah 1',
          dayOverrides: {0: 1},
        ),
      );

      expect(even.days[0].chapters, ['Jeremiah 1', 'Jeremiah 2']);
      expect(shifted.days[0].chapters, ['Jeremiah 1']);
      expect(shifted.days[1].chapters, ['Jeremiah 2', 'Jeremiah 3']);
      // Nothing is lost — one extra day absorbs the shift.
      expect(_allChapters(shifted.days), _allChapters(even.days));
      expect(shifted.days.length, even.days.length + 1);
    });

    test('effectiveCounts reports what each day actually holds', () {
      final plan = ScheduleGenerator.planFromDraft(
        _draft(
          books: ['Jeremiah'],
          startRef: 'Jeremiah 1',
          dayOverrides: {0: 1, 1: 3},
        ),
      );

      expect(plan.effectiveCounts.take(3), [1, 3, 2]);
    });
  });

  group('dates', () {
    test('honours the selected weekdays', () {
      // 1 Sep 2026 is a Tuesday; Mon/Wed only.
      final plan = ScheduleGenerator.planFromDraft(
        _draft(
          books: ['Jonah'],
          startRef: 'Jonah 1',
          weekdays: const [1, 3],
        ),
      );

      expect(plan.days.map((d) => d.date.weekday), everyElement(anyOf(1, 3)));
      expect(plan.days.first.date, DateTime(2026, 9, 2)); // Wednesday
      expect(plan.days[1].date, DateTime(2026, 9, 7)); // Monday
    });

    test('end-date mode overshoots rather than cramming', () {
      // Three one-chapter books cannot share days, so they need three days even
      // though only two were asked for.
      final plan = ScheduleGenerator.planFromDraft(
        _draft(
          books: ['Jude', 'Philemon', 'Obadiah'],
          startRef: 'Jude 1',
          chaptersPerDay: null,
          endDate: DateTime(2026, 9, 2),
        ),
      );

      expect(plan.days, hasLength(3));
      expect(plan.days.last.date, DateTime(2026, 9, 3));
    });
  });

  group('guards', () {
    test('no books yields no days', () {
      expect(
        ScheduleGenerator.planFromDraft(_draft(books: [], startRef: '')).days,
        isEmpty,
      );
    });

    test('no weekdays yields no days', () {
      expect(
        ScheduleGenerator.planFromDraft(
          _draft(books: ['Jude'], startRef: 'Jude 1', weekdays: const []),
        ).days,
        isEmpty,
      );
    });

    test('a whole-Bible plan at one chapter a day fits under the cap', () {
      final plan = ScheduleGenerator.planFromDraft(
        _draft(
          books: ['Genesis', 'Exodus'],
          startRef: 'Genesis 1',
          chaptersPerDay: 1,
        ),
      );

      expect(plan.days, hasLength(90)); // 50 + 40
      expect(plan.truncatedAtCap, isFalse);
    });

    test('a sparse cadence stretches the dates but not the day count', () {
      // Sundays only: 150 readings across 150 weeks. The cap bounds days, not
      // calendar span, so a slow cadence must not trip it.
      final plan = ScheduleGenerator.planFromDraft(
        _draft(
          books: ['Psalm'],
          startRef: 'Psalm 1',
          chaptersPerDay: 1,
          weekdays: const [7],
        ),
      );

      expect(plan.days, hasLength(150));
      expect(plan.truncatedAtCap, isFalse);
      // First Sunday after 1 Sep 2026 is the 6th; 149 weeks later is mid-2029.
      expect(plan.days.first.date, DateTime(2026, 9, 6));
      expect(plan.days.last.date, DateTime(2029, 7, 15));
    });

    test('the longest possible plan stays inside the day cap', () {
      // The whole Bible is 1,189 chapters, so one-a-day is the longest plan
      // anyone can build. It must never be truncated.
      final plan = ScheduleGenerator.planFromDraft(
        _draft(
          books: ReferenceParser.allBooks,
          startRef: 'Genesis 1',
          chaptersPerDay: 1,
        ),
      );

      expect(plan.days, hasLength(1189));
      expect(plan.days.length, lessThan(ScheduleGenerator.maxDays));
      expect(plan.truncatedAtCap, isFalse);
    });
  });

  group('legacy generateSchedule wrapper', () {
    test('still splits across books, so old plans regenerate unchanged', () {
      // Pins bookBoundary: false on the wrapper. Flipping it would silently
      // reshape every plan saved through the old call path.
      final days = ScheduleGenerator.generateSchedule(
        books: ['Jude', 'Philemon'],
        startDate: DateTime(2026, 9, 1),
        fixedChaptersPerDay: 2,
        selectedWeekdays: const [1, 2, 3, 4, 5, 6, 7],
      );

      expect(days, hasLength(1));
      expect(days.single.chapters, ['Jude 1', 'Philemon 1']);
    });

    test('starts at chapter one of the first book', () {
      final days = ScheduleGenerator.generateSchedule(
        books: ['Jonah'],
        startDate: DateTime(2026, 9, 1),
        fixedChaptersPerDay: 1,
        selectedWeekdays: const [1, 2, 3, 4, 5, 6, 7],
      );

      expect(days.first.chapters, ['Jonah 1']);
      expect(days, hasLength(4));
    });
  });
}
