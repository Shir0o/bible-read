import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/group_schedule.dart';
import '../models/group.dart';
import 'error_logger.dart';

/// Names of Firestore collections used for group features.
class GroupCollections {
  GroupCollections._();

  /// Top-level groups collection.
  static const String groups = 'groups';

  /// Sub-collection containing group members.
  static const String members = 'members';

  /// Sub-collection containing the reading schedule.
  static const String schedule = 'schedule';
}

/// Provides helper methods for managing reading groups.
class GroupService {
  /// Firestore instance used for database operations.
  final FirebaseFirestore firestore;

  /// Creates a [GroupService] using [FirebaseFirestore.instance] by default.
  GroupService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  /// Create a new group owned by [ownerUid] with [name].
  ///
  /// Returns the id of the created group.
  Future<String> createGroup({
    required String ownerUid,
    required String name,
  }) async {
    try {
      final doc = firestore.collection(GroupCollections.groups).doc();
      await doc.set({'name': name, 'ownerUid': ownerUid});
      await doc.collection(GroupCollections.members).doc(ownerUid).set({
        'uid': ownerUid,
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
      });
      return doc.id;
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  /// Join the group with [groupId] as [uid].
  Future<void> joinGroup({required String groupId, required String uid}) async {
    try {
      final memberRef = firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.members)
          .doc(uid);
      final snap = await memberRef.get();
      final data = <String, dynamic>{
        'uid': uid,
        'role': 'member',
      };
      if (!snap.exists) {
        data['joinedAt'] = FieldValue.serverTimestamp();
      }
      await memberRef.set(data, SetOptions(merge: true));
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  /// Leave the group with [groupId] as [uid].
  Future<void> leaveGroup({
    required String groupId,
    required String uid,
  }) async {
    try {
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.members)
          .doc(uid)
          .delete();
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  /// Update or create a [schedule] entry for [groupId].
  Future<void> updateSchedule({
    required String groupId,
    required GroupSchedule schedule,
  }) async {
    try {
      final docId = _dateId(schedule.date);
      final utcDate = DateTime.utc(
          schedule.date.year, schedule.date.month, schedule.date.day);
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.schedule)
          .doc(docId)
          .set({
        'date': Timestamp.fromDate(utcDate),
        'chapters': schedule.chapters,
      });
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  /// Delete the schedule entry on [date] for [groupId].
  Future<void> deleteSchedule({
    required String groupId,
    required DateTime date,
  }) async {
    try {
      final docId = _dateId(date);
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.schedule)
          .doc(docId)
          .delete();
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  /// Fetch the chapters scheduled for today for [groupId].
  Future<List<String>> fetchTodaysChapters(String groupId) async {
    try {
      final docId = _dateId(DateTime.now());
      final doc = await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.schedule)
          .doc(docId)
          .get();
      if (!doc.exists) return <String>[];
      return GroupSchedule.fromFirestore(doc).chapters;
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      return <String>[];
    }
  }

  static String _dateId(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Stream of groups the user with [uid] belongs to.
  Stream<List<Group>> groupsForUser(String uid) {
    final snaps = firestore
        .collectionGroup(GroupCollections.members)
        .where('uid', isEqualTo: uid)
        .snapshots()
        .handleError((e, st) => ErrorLogger.log(e, st));
    return snaps.asyncMap((snap) async {
      try {
        final futures = snap.docs
            .map((doc) => doc.reference.parent.parent)
            .whereType<DocumentReference<Map<String, dynamic>>>()
            .map((parent) => parent.get())
            .toList();
        final docs = await Future.wait(futures);
        return docs
            .where((doc) => doc.exists)
            .map(Group.fromFirestore)
            .toList();
      } catch (e, st) {
        await ErrorLogger.log(e, st);
        return <Group>[];
      }
    });
  }

  /// Stream of member display names for [groupId].
  Stream<List<String>> memberNames(String groupId) {
    final snaps = firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.members)
        .snapshots()
        .handleError((e, st) => ErrorLogger.log(e, st));
    return snaps.asyncMap((snap) async {
      try {
        final futures = snap.docs.map((doc) async {
          final userDoc = await firestore.collection('users').doc(doc.id).get();
          if (!userDoc.exists) return null;
          return userDoc.data()?['name'] as String? ?? '';
        }).toList();
        final names = await Future.wait<String?>(futures);
        return names.whereType<String>().toList();
      } catch (e, st) {
        await ErrorLogger.log(e, st);
        return <String>[];
      }
    });
  }

  /// Stream of schedule entries for [groupId] ordered by date.
  Stream<List<GroupSchedule>> schedule(String groupId) {
    final snaps = firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.schedule)
        .orderBy('date')
        .snapshots()
        .handleError((e, st) => ErrorLogger.log(e, st));
    return snaps.asyncMap((snap) async {
      try {
        return snap.docs.map(GroupSchedule.fromFirestore).toList();
      } catch (e, st) {
        await ErrorLogger.log(e, st);
        return <GroupSchedule>[];
      }
    });
  }
}
