// Pure remap of per-chapter progress when a group's schedule regenerates.
//
// The progress data model is positional — items/{index} keys mean "the
// chapter at position [index] in that day's `chapters` array" — so a tick
// only retains its meaning if we resolve it back to a chapter reference,
// then re-mark that reference against the new schedule.
//
// This file is intentionally free of Firestore / `Timestamp` / `DateTime`
// dependencies so the same logic ports verbatim to the Cloud Function in
// `functions/index.js` for the cross-member eager path (Phase 5b). The
// caller supplies the [dateIdOf] formatter so the cloud port can use the
// same `YYYY-MM-DD` shape without dragging in a platform dependency.
//
// Legacy representation: a day may carry `entries/{uid}.done == true`
// without any items subcollection. The caller expresses that by passing an
// empty `Set<int>` for that date — meaning "every chapter on that day is
// ticked" — and the remap expands it before walking references.
import '../models/group_schedule.dart';

/// Outcome of a remap: where each member's ticked chapters land in the new
/// plan, and which chapters disappeared with the old plan.
class ProgressRemap {
  /// The ticks that survive the move: dateId -> indices ticked for that uid.
  final Map<String, Map<String, Set<int>>> byDate;

  /// Chapter references the member had read but which no longer appear in
  /// the new schedule — full references, so the dialog can name the book.
  final Map<String, Set<String>> droppedRefs;

  /// Same chapters as [droppedRefs] but bucketed by book, so the dialog can
  /// phrase "66 chapters of Isaiah leave the plan".
  final Map<String, Map<String, int>> droppedByBook;

  const ProgressRemap({
    required this.byDate,
    required this.droppedRefs,
    required this.droppedByBook,
  });
}

/// Rewrites every member's progress so each ticked chapter reference is
/// re-marked on whichever new day holds it.
///
/// [oldDays] / [newDays] are date-ordered lists of [GroupSchedule].
/// [completedByDate] is keyed by uid -> dateId -> set of indices ticked.
/// Out-of-range indices are silently dropped — they are common in the
/// wild, where items outlive a chapter the schedule has since removed.
///
/// [dateIdOf] formats the date that keys the new progress map; pass
/// `GroupService.dateId` in the app and the same formatter at the JS port.
ProgressRemap remapProgress({
  required List<GroupSchedule> oldDays,
  required List<GroupSchedule> newDays,
  required Map<String, Map<String, Set<int>>> completedByDate,
  String Function(DateTime)? dateIdOf,
}) {
  final fmt = dateIdOf ?? _isoDateId;

  // Index the old schedule by dateId -> list of chapter refs, so a tick at
  // (uid, dateId, index) resolves in O(1) to its chapter reference.
  final oldByDateId = <String, List<String>>{
    for (final day in oldDays) fmt(day.date): day.chapters,
  };

  // Index the new schedule by chapter ref -> (dateId, index), so a resolved
  // reference finds its new home without scanning every new day.
  final newByRef = <String, _NewPosition>{};
  for (final day in newDays) {
    final dateId = fmt(day.date);
    for (var i = 0; i < day.chapters.length; i++) {
      newByRef[day.chapters[i]] = _NewPosition(dateId, i);
    }
  }

  final byDate = <String, Map<String, Set<int>>>{};
  final droppedRefs = <String, Set<String>>{};
  final droppedByBook = <String, Map<String, int>>{};

  completedByDate.forEach((uid, perDate) {
    final moved = <String, Set<int>>{};
    final dropped = <String>{};

    perDate.forEach((dateId, indices) {
      final chapters = oldByDateId[dateId];
      if (chapters == null) {
        // Date is gone entirely from the old schedule — every tick on it
        // is dropped. There is no chapter reference to attribute.
        return;
      }

      // An empty set is the legacy "whole day done" sentinel; expand it.
      final effective = indices.isEmpty
          ? [for (var i = 0; i < chapters.length; i++) i]
          : indices.toList();

      for (final index in effective) {
        if (index < 0 || index >= chapters.length) continue; // out-of-range
        final ref = chapters[index];
        final pos = newByRef[ref];
        if (pos == null) {
          dropped.add(ref);
        } else {
          moved.putIfAbsent(pos.dateId, () => <int>{}).add(pos.index);
        }
      }
    });

    if (moved.isNotEmpty) byDate[uid] = moved;
    if (dropped.isNotEmpty) {
      droppedRefs[uid] = dropped;
      final byBook = <String, int>{};
      for (final ref in dropped) {
        final book = _bookOf(ref) ?? ref;
        byBook.update(book, (n) => n + 1, ifAbsent: () => 1);
      }
      droppedByBook[uid] = byBook;
    }
  });

  return ProgressRemap(
    byDate: byDate,
    droppedRefs: droppedRefs,
    droppedByBook: droppedByBook,
  );
}

class _NewPosition {
  final String dateId;
  final int index;
  const _NewPosition(this.dateId, this.index);
}

/// `Genesis 12` -> `Genesis`. Books whose first word is the canonical name
/// (all of them) parse this way; anything else falls back to the whole
/// reference so dropped counts still sum to the right total.
String? _bookOf(String reference) {
  final trimmed = reference.trimLeft();
  if (trimmed.isEmpty) return null;
  final space = trimmed.indexOf(' ');
  if (space <= 0) return null;
  return trimmed.substring(0, space);
}

/// Mirror of `GroupService.dateId` so this file stays Firestore-free.
String _isoDateId(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
