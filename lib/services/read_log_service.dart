import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'group_collections.dart';

/// The reader's daily feed, denormalized per Group (ADR-0004, #801).
///
/// Marking a day writes one entry into every Group the reader belongs to, at
/// `groups/{id}/read_log/{date}/entries/{uid}` — the path the security rules
/// gate with a one-line membership check. A reader with no Groups writes
/// nothing and nothing errors. Reads merge every Group's entries and stream
/// live, so a co-member's mark or Amen appears without a manual refresh.
///
/// The retired global `read_logs` collection is written nowhere; its rules
/// block is gone and its path denies everything.
class ReadLogService {
  /// Creates a [ReadLogService] on [firestore] (defaults to the singleton).
  ReadLogService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  /// Firestore used for all feed operations.
  final FirebaseFirestore firestore;

  /// Firestore document id for [date].
  static String dateKeyFor(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Ids of the Groups [uid] belongs to (member or owner).
  Future<List<String>> groupIdsFor(String uid) async {
    final memberships = await firestore
        .collectionGroup(GroupCollections.members)
        .where('uid', isEqualTo: uid)
        .get();
    return memberships.docs
        .map((doc) => doc.reference.parent.parent?.id)
        .whereType<String>()
        .toSet()
        .toList();
  }

  /// Marks [user] as having read on [date] in every Group they belong to.
  ///
  /// Idempotent: re-marking the same reader and day rewrites the same
  /// documents. A reader with no Groups performs no Group writes — but the
  /// per-user `reading` document is still kept in sync, because streak
  /// calculations read it and Showing up counts without a Plan (#786).
  Future<void> mark(User user, {DateTime? date}) async {
    final now = date ?? DateTime.now();
    final dateKey = dateKeyFor(now);
    final data = {
      'uid': user.uid,
      'name': (user.displayName ?? '').split(' ').first,
      'email': user.email?.toLowerCase() ?? '',
      'dateId': dateKey,
      'timestamp': Timestamp.now(),
    };

    final groupIds = await groupIdsFor(user.uid);

    // Keep the per-user reading collection in sync for streak calculations.
    try {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('reading')
          .doc(dateKey)
          .set({'read': true}, SetOptions(merge: true));
    } catch (_) {
      // Best effort; the feed entries below are the primary record.
    }

    if (groupIds.isEmpty) return;

    final batch = firestore.batch();
    for (final groupId in groupIds) {
      batch.set(
        firestore
            .collection(GroupCollections.groups)
            .doc(groupId)
            .collection(_readLog)
            .doc(dateKey)
            .collection(_entries)
            .doc(user.uid),
        data,
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  /// Removes [user]'s entry for [date] from every Group they belong to and
  /// clears the per-user `reading` document for the day, so the streak
  /// calculations agree.
  ///
  /// Called on unmarking. Best-effort on membership lookup only; the deletes
  /// themselves are awaited so a failed unmark is observable.
  Future<void> clear(User user, {DateTime? date}) async {
    final now = date ?? DateTime.now();
    final dateKey = dateKeyFor(now);

    try {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('reading')
          .doc(dateKey)
          .set({'read': false}, SetOptions(merge: true));
    } catch (_) {
      // Best effort; the feed deletions below are the primary record.
    }

    final groupIds = await groupIdsFor(user.uid);
    if (groupIds.isEmpty) return;

    final batch = firestore.batch();
    for (final groupId in groupIds) {
      batch.delete(
        firestore
            .collection(GroupCollections.groups)
            .doc(groupId)
            .collection(_readLog)
            .doc(dateKey)
            .collection(_entries)
            .doc(user.uid),
      );
    }
    await batch.commit();
  }

  /// Convenience: [entriesForGroups] over the Groups [uid] belongs to.
  Stream<List<String>> entriesForGroupsForUser(
    String uid, {
    required String dateKey,
  }) async* {
    final groupIds = await groupIdsFor(uid);
    yield* entriesForGroups(groupIds, dateKey: dateKey);
  }

  /// Live stream of the uids with an entry on [dateKey] across [groupIds],
  /// deduplicated. Entries appear as their authors mark; likes and other
  /// sub-writes ride on the same snapshot stream. Empty for no Groups.
  Stream<List<String>> entriesForGroups(
    List<String> groupIds, {
    required String dateKey,
  }) {
    if (groupIds.isEmpty) return Stream.value(const <String>[]);

    return Stream<List<String>>.multi((controller) {
      final latest = <String, Set<String>>{
        for (final id in groupIds) id: <String>{},
      };
      final reported = <String>{};

      void emit() {
        if (controller.isClosed) return;
        final merged = <String>{};
        for (final ids in latest.values) {
          merged.addAll(ids);
        }
        controller.add(merged.toList()..sort());
      }

      final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
      for (final groupId in groupIds) {
        final sub = firestore
            .collection(GroupCollections.groups)
            .doc(groupId)
            .collection(_readLog)
            .doc(dateKey)
            .collection(_entries)
            .snapshots()
            .listen(
          (snap) {
            latest[groupId] = snap.docs.map((d) => d.id).toSet();
            reported.add(groupId);
            emit();
          },
          onError: (Object e, StackTrace st) {
            latest[groupId] = <String>{};
            reported.add(groupId);
            if (reported.length == groupIds.length) {
              controller.addError(e, st);
            } else {
              emit();
            }
          },
        );
        subs.add(sub);
      }

      controller.onCancel = () {
        for (final sub in subs) {
          unawaited(sub.cancel());
        }
      };
    });
  }

  /// Live stream of the entry documents with an entry on [dateKey] across
  /// [groupIds], deduplicated by uid with the first copy winning (a reader's
  /// entries are identical across Groups). Likes live on each copy, but the
  /// liker resolves the entry through their own Group — the same copy a
  /// co-member resolves when they belong to the same Groups. Empty for no
  /// Groups.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      entryDocsForGroupsForUser(
    String uid, {
    required String dateKey,
  }) async* {
    final groupIds = await groupIdsFor(uid);
    yield* entryDocsForGroups(groupIds, dateKey: dateKey);
  }

  /// Live stream of the entry documents for [dateKey] across [groupIds],
  /// merged by uid with the first copy winning (the same reader's entries are
  /// identical across Groups). Empty for no Groups.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> entryDocsForGroups(
    List<String> groupIds, {
    required String dateKey,
  }) {
    if (groupIds.isEmpty) {
      return Stream.value(const <QueryDocumentSnapshot<Map<String, dynamic>>>[]);
    }

    return Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.multi(
      (controller) {
        final latest = <String,
            Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>>{
          for (final id in groupIds) id: <String,
              QueryDocumentSnapshot<Map<String, dynamic>>>{},
        };
        final reported = <String>{};

        void emit() {
          if (controller.isClosed) return;
          final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
          for (final docs in latest.values) {
            for (final entry in docs.entries) {
              merged.putIfAbsent(entry.key, () => entry.value);
            }
          }
          controller.add(merged.values.toList());
        }
        final subs =
            <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
        for (final groupId in groupIds) {
          final sub = firestore
              .collection(GroupCollections.groups)
              .doc(groupId)
              .collection(_readLog)
              .doc(dateKey)
              .collection(_entries)
              .snapshots()
              .listen(
            (snap) {
              latest[groupId] = {
                for (final doc in snap.docs) doc.id: doc,
              };
              reported.add(groupId);
              emit();
            },
            onError: (Object e, StackTrace st) {
              latest[groupId] = {};
              reported.add(groupId);
              if (reported.length == groupIds.length) {
                controller.addError(e, st);
              } else {
                emit();
              }
            },
          );
          subs.add(sub);
        }

        controller.onCancel = () {
          for (final sub in subs) {
            unawaited(sub.cancel());
          }
        };
      },
    );
  }
}

const String _readLog = 'read_log';
const String _entries = 'entries';