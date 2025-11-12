import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/group_schedule.dart';
import 'group_service.dart';
import 'reference_parser.dart';

/// Aggregates completed chapters across all of a user's groups.
class GroupBookAchievementService {
  GroupBookAchievementService({
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
  /// numbers for [uid] across all joined or owned groups.
  Future<Map<String, Set<int>>> completedChaptersByBook(String uid) async {
    final groups = await groupService.groupsForUser(uid).first;
    if (groups.isEmpty) {
      return <String, Set<int>>{};
    }

    final Map<String, Set<int>> result = {};
    for (final group in groups) {
      final groupRef =
          firestore.collection(GroupCollections.groups).doc(group.id);
      final scheduleSnap =
          await groupRef.collection(GroupCollections.schedule).get();
      for (final scheduleDoc in scheduleSnap.docs) {
        final schedule = GroupSchedule.fromFirestore(scheduleDoc);
        if (schedule.chapters.isEmpty) {
          continue;
        }
        final dateId =
            scheduleDoc.id.isNotEmpty ? scheduleDoc.id : _dateId(schedule.date);
        final entryRef = groupRef
            .collection('progress')
            .doc(dateId)
            .collection('entries')
            .doc(uid);
        final entrySnap = await entryRef.get();
        if (!entrySnap.exists) {
          continue;
        }
        final checkedIndices =
            await _loadCheckedIndices(entrySnap, schedule.chapters.length);
        if (checkedIndices.isEmpty) {
          continue;
        }
        for (final index in checkedIndices) {
          if (index < 0 || index >= schedule.chapters.length) {
            continue;
          }
          final chapter = _parseChapter(schedule.chapters[index]);
          if (chapter == null) {
            continue;
          }
          result.putIfAbsent(chapter.book, () => <int>{}).add(chapter.chapter);
        }
      }
    }

    return result.map(
      (book, chapters) => MapEntry(book, Set<int>.unmodifiable(chapters)),
    );
  }

  Future<Set<int>> _loadCheckedIndices(
    DocumentSnapshot<Map<String, dynamic>> entrySnap,
    int totalChapters,
  ) async {
    final itemsSnap = await entrySnap.reference.collection('items').get();
    final checked = <int>{};
    for (final item in itemsSnap.docs) {
      final index = int.tryParse(item.id);
      if (index != null) {
        checked.add(index);
      }
    }
    if (checked.isNotEmpty) {
      return checked;
    }

    final data = entrySnap.data() ?? <String, dynamic>{};
    final done = data['done'] == true;
    final count = (data['count'] as num?)?.toInt() ?? 0;
    if (totalChapters > 0 && (done || count >= totalChapters)) {
      return Set<int>.from(List<int>.generate(totalChapters, (i) => i));
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
