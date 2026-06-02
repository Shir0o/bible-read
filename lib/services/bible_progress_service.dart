import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/group_schedule.dart';
import 'group_service.dart';
import 'reference_parser.dart';

/// Aggregates completed chapters across all of a user's groups.
class BibleProgressService {
  BibleProgressService({
    FirebaseFirestore? firestore,
    GroupService? groupService,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        groupService = groupService ??
            GroupService(firestore: firestore ?? FirebaseFirestore.instance);

  /// Firestore instance used for reads.
  final FirebaseFirestore firestore;

  /// Group service used to enumerate membership.
  final GroupService groupService;

  /// Returns a map from canonical book names to the set of completed chapter
  /// numbers for [uid] across all joined or owned groups, plus any manually
  /// completed books.
  Future<Map<String, Set<int>>> completedChaptersByBook(String uid) async {
    // 1. Fetch all progress entries for the user in one query.
    // This avoids N queries where N is the total number of scheduled days across all groups.
    // Also fetch manual book completions in parallel.
    final futures = await Future.wait([
      firestore.collectionGroup('entries').where('uid', isEqualTo: uid).get(),
      firestore.collection('users').doc(uid).collection('bible_books').get(),
    ]);

    final allEntriesSnap = futures[0];
    final manualBooksSnap = futures[1];

    // Organize entries by groupId -> dateId -> DocumentSnapshot
    final entriesByGroup = <String, Map<String, DocumentSnapshot>>{};
    for (final doc in allEntriesSnap.docs) {
      // Path: groups/{groupId}/progress/{dateId}/entries/{uid}
      // Segments: 0      1         2         3        4      5
      final segments = doc.reference.path.split('/');
      if (segments.length < 6) continue;
      final groupId = segments[1];
      final dateId = segments[3];

      entriesByGroup.putIfAbsent(groupId, () => {})[dateId] = doc;
    }

    // 2. Fetch all groups for the user.
    final groups = await groupService.groupsForUser(uid).first;

    // 3. Process each group in parallel.
    final groupFutures = groups.map((group) async {
      final groupEntries = entriesByGroup[group.id];
      if (groupEntries == null || groupEntries.isEmpty) {
        return <String, Set<int>>{};
      }

      final groupRef =
          firestore.collection(GroupCollections.groups).doc(group.id);
      final scheduleSnap =
          await groupRef.collection(GroupCollections.schedule).get();

      // Process all schedule items in parallel
      final itemFutures = scheduleSnap.docs.map((scheduleDoc) async {
        final schedule = GroupSchedule.fromFirestore(scheduleDoc);
        if (schedule.chapters.isEmpty) {
          return null;
        }

        final dateId =
            scheduleDoc.id.isNotEmpty ? scheduleDoc.id : _dateId(schedule.date);
        final entrySnap = groupEntries[dateId];
        if (entrySnap == null) {
          return null;
        }

        // Check completion status
        final checkedIndices = await _loadCheckedIndices(
          entrySnap,
          schedule.chapters.length,
        );

        if (checkedIndices.isEmpty) {
          return null;
        }

        final localResult = <String, Set<int>>{};
        for (final index in checkedIndices) {
          if (index < 0 || index >= schedule.chapters.length) {
            continue;
          }
          final chapter = _parseChapter(schedule.chapters[index]);
          if (chapter == null) {
            continue;
          }
          localResult
              .putIfAbsent(chapter.book, () => <int>{})
              .add(chapter.chapter);
        }
        return localResult;
      });

      final itemResults = await Future.wait(itemFutures);

      // Merge results for this group
      final groupResult = <String, Set<int>>{};
      for (final res in itemResults) {
        if (res == null) continue;
        res.forEach((book, chapters) {
          groupResult.putIfAbsent(book, () => <int>{}).addAll(chapters);
        });
      }
      return groupResult;
    });

    final groupResults = await Future.wait(groupFutures);

    // 4. Merge all group results
    final finalResult = <String, Set<int>>{};
    for (final res in groupResults) {
      res.forEach((book, chapters) {
        finalResult.putIfAbsent(book, () => <int>{}).addAll(chapters);
      });
    }

    // 5. Add manual book completions
    for (final doc in manualBooksSnap.docs) {
      final book = doc.id; // doc ID is the book name (canonical)
      if (ReferenceParser.allBooks.contains(book)) {
        final count = ReferenceParser.chapterCount(book) ?? 0;
        if (count > 0) {
          final chapters = Set<int>.from(
            List<int>.generate(count, (i) => i + 1),
          );
          finalResult[book] = chapters;
        }
      }
    }

    return finalResult.map(
      (book, chapters) => MapEntry(book, Set<int>.unmodifiable(chapters)),
    );
  }

  /// Returns the name of the book most recently marked as completed by [uid].
  Future<String?> getLastCheckedBook(String uid) async {
    try {
      final snap = await firestore
          .collection('users')
          .doc(uid)
          .collection('bible_books')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        return snap.docs.first.id;
      }
    } catch (e) {
      debugPrint('Error getting last checked book: $e');
    }
    return null;
  }

  Future<Set<int>> _loadCheckedIndices(
    DocumentSnapshot entrySnap,
    int totalChapters,
  ) async {
    // Optimization: Check the 'done' flag or 'count' first to avoid fetching items.
    final data = entrySnap.data() as Map<String, dynamic>? ?? {};
    final done = data['done'] == true;
    final count = (data['count'] as num?)?.toInt() ?? 0;

    if (totalChapters > 0 && (done || count >= totalChapters)) {
      return Set<int>.from(List<int>.generate(totalChapters, (i) => i));
    }

    // If not fully done according to summary fields, fetch items (partial progress).
    final itemsSnap = await entrySnap.reference.collection('items').get();
    final checked = <int>{};
    for (final item in itemsSnap.docs) {
      final index = int.tryParse(item.id);
      if (index != null) {
        checked.add(index);
      }
    }

    // Fallback: if items found, return them.
    if (checked.isNotEmpty) {
      return checked;
    }

    return checked;
  }

  _ChapterRef? _parseChapter(String reference) {
    final normalized = ReferenceParser.normalizeOne(reference);
    final match = RegExp(r'^(.*\S)\s+(\d+)$').firstMatch(normalized);
    if (match == null) {
      return null;
    }
    final book = match.group(1)!.trim();
    final chapter = int.tryParse(match.group(2)!) ?? 0;
    if (book.isEmpty || chapter <= 0) {
      return null;
    }
    final chapterCount = ReferenceParser.chapterCount(book);
    if (chapterCount != null && chapter > chapterCount) {
      return null;
    }
    return _ChapterRef(book, chapter);
  }

  String _dateId(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class _ChapterRef {
  const _ChapterRef(this.book, this.chapter);

  final String book;
  final int chapter;
}
