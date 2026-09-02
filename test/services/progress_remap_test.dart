// Pure remap of per-chapter progress when a group's schedule regenerates.
//
// The data model is:
//   groups/{gid}/progress/{dateId}/entries/{uid}/items/{index} keyed by the
//   POSITION in that day's `chapters` array (the chapter reference itself is
//   stored nowhere). After a regeneration, position i points at a different
//   chapter — so a tick at the old day2 index 1 may need to move to day3 index
//   0 to mean the same chapter. Old schedules also carry legacy `done == true`
//   entries with no `items` at all. The remap walks each member's ticked indices
//   back through the OLD day, normalises the resulting chapter reference, and
//   re-marks it against the NEW day.
//
// This is the core of Phase 5a. It is intentionally pure — no Firestore, no
// `Timestamp`, no `DateTime` dependencies — so the same logic can be ported
// verbatim to the Cloud Function in Phase 5b.
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/services/progress_remap.dart';

GroupSchedule _day(int d, List<String> chapters) =>
    GroupSchedule(date: DateTime(2026, 9, d), chapters: chapters);

/// `YYYY-MM-DD` matching the production `GroupService.dateId` formatter, so a
/// test author can reason about both ends of the wire at once.
String _id(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  group('remapProgress', () {
    test(
        'moves a tick from old position to the new position that means the '
        'same chapter, and nowhere else', () {
      // Old plan: day 1 = Jeremiah 1-2, day 2 = Jeremiah 3-4.
      // New plan: day 1 = Jeremiah 1, day 2 = Jeremiah 2, day 3 = Jeremiah 3-4.
      final oldDays = [
        _day(1, ['Jeremiah 1', 'Jeremiah 2']),
        _day(2, ['Jeremiah 3', 'Jeremiah 4']),
      ];
      final newDays = [
        _day(1, ['Jeremiah 1']),
        _day(2, ['Jeremiah 2']),
        _day(3, ['Jeremiah 3', 'Jeremiah 4']),
      ];

      final completed = {
        // A member who ticked day 1 = 0 ("Jeremiah 1") and day 2 = 0
        // ("Jeremiah 3"). Only one of them moves under the new plan.
        'alice': {
          '2026-09-01': {0},
          '2026-09-02': {0},
        },
      };

      final result = remapProgress(
        oldDays: oldDays,
        newDays: newDays,
        completedByDate: completed,
      );

      // Jeremiah 1 stays ticked on day 1 (it is still there at index 0).
      expect(result.byDate['alice']?['2026-09-01'], {0});
      // Jeremiah 3 lands on day 3 at index 0.
      expect(result.byDate['alice']?['2026-09-02'], isNull);
      expect(result.byDate['alice']?['2026-09-03'], {0});
    });

    test(
        'drops a tick that no longer maps to any chapter in the new plan, '
        'and reports it as a dropped reference', () {
      // Old plan started at Isaiah 1; new plan starts at Jeremiah 1.
      final oldDays = [
        _day(1, ['Isaiah 1']),
        _day(2, ['Isaiah 2'])
      ];
      final newDays = [
        _day(1, ['Jeremiah 1']),
        _day(2, ['Jeremiah 2'])
      ];

      final result = remapProgress(
        oldDays: oldDays,
        newDays: newDays,
        completedByDate: {
          'bob': {
            '2026-09-01': {0}, // Isaiah 1 — no longer scheduled.
            '2026-09-02': {0}, // Isaiah 2 — no longer scheduled.
          },
        },
      );

      // Both ticks disappear; no chapter in the new plan was ticked.
      expect(result.byDate['bob'], isNull);
      // Both Isaiah references surface as dropped.
      expect(result.droppedRefs['bob'], {'Isaiah 1', 'Isaiah 2'});
    });

    test(
        'treats a legacy entries/{uid}.done == true day with no items as '
        'marking every chapter on that day, and re-marks each of them', () {
      // The legacy representation marks the whole day done without per-chapter
      // items. The caller passes an empty set for such a day and the remap
      // should expand it to "every chapter on that day".
      final oldDays = [
        _day(1, ['Jonah 1', 'Jonah 2', 'Jonah 3'])
      ];
      final newDays = [
        _day(1, ['Jonah 1']),
        _day(2, ['Jonah 2']),
        _day(3, ['Jonah 3']),
      ];

      // Pass empty indices for the legacy "whole day done" sentinel.
      final result = remapProgress(
        oldDays: oldDays,
        newDays: newDays,
        completedByDate: {
          'carol': {'2026-09-01': <int>{}},
        },
      );

      expect(result.byDate['carol']?['2026-09-01'], {0});
      expect(result.byDate['carol']?['2026-09-02'], {0});
      expect(result.byDate['carol']?['2026-09-03'], {0});
      expect(result.droppedRefs['carol'], isNull);
    });

    test('silently drops out-of-range indices that exist in the wild', () {
      // Real schedules have stranded tick indices when an items subcollection
      // outlives a chapter that has been deleted from the schedule. They must
      // not crash the remap and they must not be reported as dropped — there
      // is no chapter reference to report.
      final oldDays = [
        _day(1, ['Jonah 1'])
      ];
      final newDays = [
        _day(1, ['Jonah 1'])
      ];

      final result = remapProgress(
        oldDays: oldDays,
        newDays: newDays,
        completedByDate: {
          'dave': {
            '2026-09-01': {0, 99}
          }, // 99 is out of range
        },
      );

      // Only the in-range index is preserved.
      expect(result.byDate['dave']?['2026-09-01'], {0});
    });

    test('an empty old schedule is a no-op', () {
      final newDays = [
        _day(1, ['Jeremiah 1'])
      ];

      final result = remapProgress(
        oldDays: const [],
        newDays: newDays,
        completedByDate: {
          'eve': {
            '2026-09-01': {0}
          },
        },
      );

      expect(result.byDate, isEmpty);
      expect(result.droppedRefs, isEmpty);
    });

    test('reports dropped references by book for the dialog', () {
      // Owner removes Isaiah from the plan; whoever had ticked Isaiah keeps
      // them but the dialog should be able to say "66 chapters of Isaiah
      // leave the plan" — by book, not just count.
      //
      // Date keys are spelled out so it is independent of local time-zone
      // arithmetic; the production formatter does the same.
      final oldDays = <GroupSchedule>[];
      final oldKeys = <String>[];
      for (var i = 0; i < 66; i++) {
        final base = DateTime(2026, 9, 1);
        final date = DateTime(base.year, base.month, base.day + i);
        oldDays.add(GroupSchedule(date: date, chapters: ['Isaiah ${i + 1}']));
        oldKeys.add(_id(date));
      }
      final newDays = [
        _day(1, ['Jeremiah 1'])
      ];

      final result = remapProgress(
        oldDays: oldDays,
        newDays: newDays,
        completedByDate: {
          'frank': {
            for (final key in oldKeys) key: {0},
          },
        },
      );

      expect(result.droppedByBook['frank'], {'Isaiah': 66});
    });
  });
}
