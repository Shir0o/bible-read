import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group_plan_config.dart';
import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/models/schedule_mode.dart';

void main() {
  group('GroupPlanDraft.fromMap', () {
    test('a missing planConfig reads as the initial draft', () {
      final today = DateTime(2026, 9, 1);
      expect(
        GroupPlanDraft.fromMap(null),
        GroupPlanDraft.initial(startDate: DateTime.now()),
      );
      expect(GroupPlanDraft.initial(startDate: today).startDate, today);
    });

    test('an empty map reads as the initial draft', () {
      expect(GroupPlanDraft.fromMap(const {}), GroupPlanDraft.initial());
    });

    test('round-trips through Firestore with int-keyed day overrides', () {
      final draft = GroupPlanDraft(
        books: const ['Isaiah', 'Jeremiah'],
        startRef: 'Jeremiah 1',
        mode: ScheduleMode.chaptersPerDay,
        chaptersPerDay: 2,
        startDate: DateTime(2026, 9, 1),
        endDate: null,
        weekdays: const [1, 3, 5],
        bookBoundary: true,
        dayOverrides: const {0: 1, 1: 2},
        revision: 4,
      );

      expect(GroupPlanDraft.fromMap(draft.toFirestore()), draft);
    });

    test('writes day-override keys as strings', () {
      final map = GroupPlanDraft.initial()
          .copyWith(dayOverrides: const {0: 1, 12: 3}).toFirestore();

      expect(map['dayOverrides'], {'0': 1, '12': 3});
    });

    test('an end date survives the round trip', () {
      final draft = GroupPlanDraft.initial().copyWith(
        books: const ['Jonah'],
        startRef: 'Jonah 1',
        endDate: DateTime(2026, 11, 26),
      );

      expect(GroupPlanDraft.fromMap(draft.toFirestore()).endDate,
          DateTime(2026, 11, 26));
    });

    test('tolerates a malformed dayOverrides map', () {
      final restored = GroupPlanDraft.fromMap({
        'dayOverrides': {'nope': 'x', '2': 3},
      });

      expect(restored.dayOverrides, {2: 3});
    });

    test('falls back to reading every day when weekdays are missing', () {
      expect(
        GroupPlanDraft.fromMap({'books': <String>[]}).weekdays,
        [1, 2, 3, 4, 5, 6, 7],
      );
    });
  });

  group('GroupPlanDraft.initial', () {
    test('keeps books on their own days', () {
      expect(GroupPlanDraft.initial().bookBoundary, isTrue);
    });
  });

  group('GroupPlanDraft.inferFromSchedule', () {
    GroupSchedule day(int d, List<String> chapters) =>
        GroupSchedule(date: DateTime(2026, 9, d), chapters: chapters);

    test('recovers the starting chapter a legacy plan did not store', () {
      // The whole point: without this the edit screen resets a plan that
      // starts at Jeremiah 1 back to Isaiah 1.
      final draft = GroupPlanDraft.inferFromSchedule([
        day(1, ['Jeremiah 1']),
        day(2, ['Jeremiah 2', 'Jeremiah 3']),
      ]);

      expect(draft.startRef, 'Jeremiah 1');
      expect(draft.books, ['Jeremiah']);
      expect(draft.startDate, DateTime(2026, 9, 1));
      expect(draft.endDate, DateTime(2026, 9, 2));
    });

    test('keeps books in reading order, not alphabetical', () {
      final draft = GroupPlanDraft.inferFromSchedule([
        day(1, ['Revelation 1']),
        day(2, ['Genesis 1']),
        day(3, ['Amos 1']),
      ]);

      expect(draft.books, ['Revelation', 'Genesis', 'Amos']);
    });

    test('does not invent a book boundary or hand-set days', () {
      // A legacy schedule was generated without either; assuming them would
      // reshape a plan nobody asked to reshape.
      final draft = GroupPlanDraft.inferFromSchedule([
        day(1, ['Obadiah 1', 'Jonah 1']),
      ]);

      expect(draft.bookBoundary, isFalse);
      expect(draft.dayOverrides, isEmpty);
    });

    test('recovers the reading cadence from the dates used', () {
      final draft = GroupPlanDraft.inferFromSchedule([
        GroupSchedule(date: DateTime(2026, 9, 7), chapters: const ['Jonah 1']),
        GroupSchedule(date: DateTime(2026, 9, 9), chapters: const ['Jonah 2']),
        GroupSchedule(date: DateTime(2026, 9, 14), chapters: const ['Jonah 3']),
      ]);

      expect(draft.weekdays, [1, 3]);
    });

    test('an empty schedule reads as the initial draft', () {
      expect(
          GroupPlanDraft.inferFromSchedule(const []), GroupPlanDraft.initial());
    });

    test('a day with unparseable chapters contributes no books', () {
      final draft = GroupPlanDraft.inferFromSchedule([
        day(1, ['Nonsense 1']),
      ]);

      expect(draft.books, isEmpty);
    });
  });

  group('copyWith', () {
    test('clears the end date on request', () {
      final draft = GroupPlanDraft.initial().copyWith(
        endDate: DateTime(2026, 12, 1),
      );

      expect(draft.copyWith(clearEndDate: true).endDate, isNull);
      expect(draft.copyWith().endDate, DateTime(2026, 12, 1));
    });

    test('clears the chapter pace on request', () {
      final draft = GroupPlanDraft.initial().copyWith(chaptersPerDay: 3);

      expect(draft.copyWith(clearChaptersPerDay: true).chaptersPerDay, isNull);
      expect(draft.copyWith().chaptersPerDay, 3);
    });
  });

  group('toFirestore', () {
    test('normalises dates to UTC midnight', () {
      final map =
          GroupPlanDraft.initial(startDate: DateTime(2026, 9, 1, 13, 45))
              .toFirestore();

      expect(
        (map['startDate'] as Timestamp).toDate().toUtc(),
        DateTime.utc(2026, 9, 1),
      );
    });
  });
}
