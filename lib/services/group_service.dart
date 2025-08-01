import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/group_schedule.dart';
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
    final doc = firestore.collection(GroupCollections.groups).doc();
    await doc.set({'name': name, 'ownerUid': ownerUid});
    await doc
        .collection(GroupCollections.members)
        .doc(ownerUid)
        .set({'owner': true});
    return doc.id;
  }

  /// Join the group with [groupId] as [uid].
  Future<void> joinGroup({required String groupId, required String uid}) async {
    await firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.members)
        .doc(uid)
        .set({});
  }

  /// Leave the group with [groupId] as [uid].
  Future<void> leaveGroup(
      {required String groupId, required String uid}) async {
    await firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.members)
        .doc(uid)
        .delete()
        .catchError((e, st) => ErrorLogger.log(e, st));
  }

  /// Update or create a [schedule] entry for [groupId].
  Future<void> updateSchedule({
    required String groupId,
    required GroupSchedule schedule,
  }) async {
    final docId = _dateId(schedule.date);
    await firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.schedule)
        .doc(docId)
        .set(schedule.toFirestore());
  }

  /// Fetch the chapters scheduled for today for [groupId].
  Future<List<String>> fetchTodaysChapters(String groupId) async {
    final docId = _dateId(DateTime.now());
    final doc = await firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.schedule)
        .doc(docId)
        .get();
    if (!doc.exists) return <String>[];
    return GroupSchedule.fromFirestore(doc).chapters;
  }

  static String _dateId(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
