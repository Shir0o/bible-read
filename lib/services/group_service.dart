import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';
import '../models/group_schedule.dart';
import '../models/group.dart';
import '../models/notification_preferences.dart';
import 'error_logger.dart';
import 'notification_service.dart';

/// Names of Firestore collections used for group features.
class GroupCollections {
  GroupCollections._();

  /// Top-level groups collection.
  static const String groups = 'groups';

  /// Sub-collection containing group members.
  static const String members = 'members';

  /// Sub-collection containing the reading schedule.
  static const String schedule = 'schedule';

  /// Sub-collection containing join requests awaiting approval.
  static const String joinRequests = 'joinRequests';
}

/// Provides helper methods for managing reading groups.
class GroupService {
  /// Firestore instance used for database operations.
  final FirebaseFirestore firestore;

  /// Service for writing notification documents.
  final NotificationService notificationService;

  /// Creates a [GroupService] using [FirebaseFirestore.instance] by default.
  GroupService({FirebaseFirestore? firestore, NotificationService? notificationService})
      : firestore = firestore ?? FirebaseFirestore.instance,
        notificationService =
            notificationService ?? NotificationService(firestore: firestore ?? FirebaseFirestore.instance);

  /// Create a new group owned by [ownerUid] with [name].
  ///
  /// [isPublic] controls whether the group is publicly visible.
  ///
  /// Returns the id of the created group.
  Future<String> createGroup({
    required String ownerUid,
    required String name,
    bool isPublic = true,
  }) async {
    try {
      final doc = firestore.collection(GroupCollections.groups).doc();
      await doc.set({
        'name': name,
        'ownerUid': ownerUid,
        'isPublic': isPublic,
      });
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
  ///
  /// If the group is not public a join request will be created instead.
  Future<void> joinGroup({
    required String groupId,
    required String uid,
    required String name,
  }) async {
    try {
      final groupDoc = await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .get();
      final isPublic = groupDoc.data()?['isPublic'] as bool? ?? true;
      if (!isPublic) {
        await requestJoin(groupId: groupId, uid: uid, name: name);
        return;
      }

      final memberRef = firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.members)
          .doc(uid);
      final snap = await memberRef.get();
      final data = <String, dynamic>{'uid': uid, 'name': name};
      if (snap.exists) {
        final role = snap.data()?['role'];
        if (role != null) data['role'] = role;
      } else {
        data['role'] = 'member';
        data['joinedAt'] = FieldValue.serverTimestamp();
      }
      await memberRef.set(data, SetOptions(merge: true));
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  /// Create a join request for [uid] on [groupId].
  Future<void> requestJoin({
    required String groupId,
    required String uid,
    required String name,
  }) async {
    try {
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.joinRequests)
          .doc(uid)
          .set({
        'uid': uid,
        'name': name,
        'requestedAt': FieldValue.serverTimestamp(),
      });

      final groupSnap = await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .get();
      final ownerUid = groupSnap.data()?['ownerUid'] as String?;
      if (ownerUid != null && ownerUid != uid) {
        final notificationId = firestore
            .collection(NotificationCollections.users)
            .doc(ownerUid)
            .collection(NotificationCollections.notifications)
            .doc()
            .id;
        final notification = AppNotification(
          id: notificationId,
          type: NotificationType.friendRequest,
          fromUid: uid,
          senderUid: uid,
          timestamp: DateTime.now(),
          read: false,
        );
        await notificationService.addNotification(ownerUid, notification);
      }
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  /// Approve a join request for [uid] on [groupId].
  Future<void> approveJoinRequest({
    required String groupId,
    required String uid,
  }) async {
    try {
      final groupRef =
          firestore.collection(GroupCollections.groups).doc(groupId);
      final requestRef =
          groupRef.collection(GroupCollections.joinRequests).doc(uid);
      final requestSnap = await requestRef.get();
      final name = requestSnap.data()?['name'] as String?;

      final memberRef =
          groupRef.collection(GroupCollections.members).doc(uid);
      final data = <String, dynamic>{
        'uid': uid,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      };
      if (name != null && name.isNotEmpty) {
        data['name'] = name;
      }
      await memberRef.set(data, SetOptions(merge: true));
      await requestRef.delete();
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  /// Deny a join request for [uid] on [groupId].
  Future<void> denyJoinRequest({
    required String groupId,
    required String uid,
  }) async {
    try {
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.joinRequests)
          .doc(uid)
          .delete();
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

  /// Stream of all groups in the database.
  Stream<List<Group>> allGroups() {
    return Stream<List<Group>>.multi((controller) {
      final sub =
          firestore.collection(GroupCollections.groups).snapshots().listen(
        (snap) async {
          try {
            controller.add(
              snap.docs.map(Group.fromFirestore).toList(),
            );
          } catch (e, st) {
            await ErrorLogger.log(e, st);
            controller.add(<Group>[]);
          }
        },
        onError: (e, st) async {
          await ErrorLogger.log(e, st);
          controller.add(<Group>[]);
        },
      );

      controller.onCancel = () => sub.cancel();
    });
  }

  /// Stream of groups the user with [uid] belongs to or owns.
  Stream<List<Group>> groupsForUser(String uid) {
    final memberSnaps = firestore
        .collectionGroup(GroupCollections.members)
        .where('uid', isEqualTo: uid)
        .snapshots();

    final ownerSnaps = firestore
        .collection(GroupCollections.groups)
        .where('ownerUid', isEqualTo: uid)
        .snapshots();

    return Stream<List<Group>>.multi((controller) {
      var memberGroups = <Group>[];
      var ownerGroups = <Group>[];

      Future<void> emit() async {
        final merged = <String, Group>{};
        for (final g in memberGroups) {
          merged[g.id] = g;
        }
        for (final g in ownerGroups) {
          merged[g.id] = g;
        }
        controller.add(merged.values.toList());
      }

      Future<void> handleMember(
          QuerySnapshot<Map<String, dynamic>> snap) async {
        try {
          final futures = snap.docs
              .map((doc) => doc.reference.parent.parent)
              .whereType<DocumentReference<Map<String, dynamic>>>()
              .map((parent) => parent.get())
              .toList();
          final docs = await Future.wait(futures);
          memberGroups =
              docs.where((doc) => doc.exists).map(Group.fromFirestore).toList();
        } catch (e, st) {
          await ErrorLogger.log(e, st);
          memberGroups = <Group>[];
        }
        await emit();
      }

      Future<void> handleOwner(QuerySnapshot<Map<String, dynamic>> snap) async {
        try {
          ownerGroups = snap.docs.map(Group.fromFirestore).toList();
        } catch (e, st) {
          await ErrorLogger.log(e, st);
          ownerGroups = <Group>[];
        }
        await emit();
      }

      final sub1 = memberSnaps.listen(
        (snap) => unawaited(handleMember(snap)),
        onError: (e, st) async {
          await ErrorLogger.log(e, st);
          memberGroups = <Group>[];
          await emit();
        },
      );
      final sub2 = ownerSnaps.listen(
        (snap) => unawaited(handleOwner(snap)),
        onError: (e, st) async {
          await ErrorLogger.log(e, st);
          ownerGroups = <Group>[];
          await emit();
        },
      );

      controller.onCancel = () {
        sub1.cancel();
        sub2.cancel();
      };
    });
  }

  /// Stream of member display names for [groupId].
  Stream<List<String>> memberNames(String groupId) {
    final snaps = firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.members)
        .snapshots()
        .handleError((e, st) {
      unawaited(ErrorLogger.log(e, st));
      throw e;
    });
    return snaps.asyncMap((snap) async {
      try {
        final names = <String>[];
        final missingUids = <String>[];

        for (final doc in snap.docs) {
          final data = doc.data();
          final name = data['name'] as String?;
          if (name != null && name.isNotEmpty) {
            names.add(name);
            continue;
          }

          final uid = data['uid'] as String?;
          if (uid != null && uid.isNotEmpty) {
            missingUids.add(uid);
          }
        }

        for (var i = 0; i < missingUids.length; i += 10) {
          final batch = missingUids.sublist(
            i,
            i + 10 > missingUids.length ? missingUids.length : i + 10,
          );
          final query = await firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: batch)
              .get();
          for (final user in query.docs) {
            final userName = user.data()['name'] as String?;
            if (userName != null && userName.isNotEmpty) {
              names.add(userName);
            }
          }
        }

        return names;
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
        .handleError((e, st) {
      unawaited(ErrorLogger.log(e, st));
      throw e;
    });
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
