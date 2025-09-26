import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';
import '../models/group_member_progress.dart';
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
  GroupService(
      {FirebaseFirestore? firestore, NotificationService? notificationService})
      : firestore = firestore ?? FirebaseFirestore.instance,
        notificationService = notificationService ??
            NotificationService(
                firestore: firestore ?? FirebaseFirestore.instance);

  /// Create a new group owned by [ownerUid] with [name].
  ///
  /// Returns the id of the created group.
  Future<String> createGroup({
    required String ownerUid,
    required String name,
  }) async {
    try {
      final doc = firestore.collection(GroupCollections.groups).doc();
      await doc.set({
        'name': name,
        'ownerUid': ownerUid,
        'memberCount': 1,
      });
      await doc.collection(GroupCollections.members).doc(ownerUid).set({
        'uid': ownerUid,
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
      });
      // Best-effort: populate owner's display name on member record.
      try {
        final userSnap =
            await firestore.collection('users').doc(ownerUid).get();
        final data = userSnap.data();
        if (data != null) {
          final n = (data['name'] as String?)?.trim();
          final dn = (data['displayName'] as String?)?.trim();
          final em = (data['email'] as String?)?.trim();
          String? chosen = n?.isNotEmpty == true
              ? n
              : dn?.isNotEmpty == true
                  ? dn
                  : (em?.isNotEmpty == true
                      ? (em!.contains('@')
                          ? em.substring(0, em.indexOf('@'))
                          : em)
                      : null);
          if (chosen != null && chosen.isNotEmpty) {
            await doc
                .collection(GroupCollections.members)
                .doc(ownerUid)
                .set({'name': chosen}, SetOptions(merge: true));
          }
        }
      } catch (e, st) {
        await ErrorLogger.log(e, st);
      }
      return doc.id;
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  /// Join the group with [groupId] as [uid].
  ///
  /// This always creates a join request for the group owner to approve.
  Future<void> joinGroup({
    required String groupId,
    required String uid,
    required String name,
  }) {
    return requestJoin(groupId: groupId, uid: uid, name: name);
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
          type: NotificationType.groupJoinRequest,
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

      final memberRef = groupRef.collection(GroupCollections.members).doc(uid);
      final memberSnap = await memberRef.get();
      final data = <String, dynamic>{
        'uid': uid,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      };
      if (name != null && name.isNotEmpty) {
        data['name'] = name;
      }
      final batch = firestore.batch();
      batch.set(memberRef, data, SetOptions(merge: true));
      if (!memberSnap.exists) {
        await _ensureMemberCount(groupRef);
        batch.update(groupRef, {'memberCount': FieldValue.increment(1)});
      }
      batch.delete(requestRef);
      await batch.commit();
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
      final groupRef =
          firestore.collection(GroupCollections.groups).doc(groupId);
      final memberRef = groupRef.collection(GroupCollections.members).doc(uid);
      final memberSnap = await memberRef.get();
      if (!memberSnap.exists) {
        return;
      }
      await _ensureMemberCount(groupRef);
      final batch = firestore.batch();
      batch.delete(memberRef);
      batch.update(groupRef, {'memberCount': FieldValue.increment(-1)});
      await batch.commit();
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  /// Promote the member with [uid] to `admin` when requested by [ownerUid].
  Future<void> promoteToAdmin({
    required String groupId,
    required String ownerUid,
    required String uid,
  }) async {
    try {
      final groupRef =
          firestore.collection(GroupCollections.groups).doc(groupId);
      final groupSnap = await groupRef.get();
      final actualOwner = groupSnap.data()?['ownerUid'] as String?;
      if (actualOwner != ownerUid) {
        throw StateError('Only the group owner can promote admins.');
      }

      if (uid == actualOwner) {
        return;
      }

      final memberRef = groupRef.collection(GroupCollections.members).doc(uid);
      final memberSnap = await memberRef.get();
      if (!memberSnap.exists) {
        throw StateError('Cannot promote a non-member.');
      }
      final currentRole = memberSnap.data()?['role'] as String?;
      if (currentRole == 'admin') {
        return;
      }
      await memberRef.update({'role': 'admin'});
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  /// Demote the member with [uid] from `admin` to `member` when requested by
  /// [ownerUid].
  Future<void> demoteAdmin({
    required String groupId,
    required String ownerUid,
    required String uid,
  }) async {
    try {
      final groupRef =
          firestore.collection(GroupCollections.groups).doc(groupId);
      final groupSnap = await groupRef.get();
      final actualOwner = groupSnap.data()?['ownerUid'] as String?;
      if (actualOwner != ownerUid) {
        throw StateError('Only the group owner can demote admins.');
      }

      if (uid == actualOwner) {
        throw StateError('The owner cannot be demoted.');
      }

      final memberRef = groupRef.collection(GroupCollections.members).doc(uid);
      final memberSnap = await memberRef.get();
      if (!memberSnap.exists) {
        throw StateError('Cannot demote a non-member.');
      }
      final currentRole = memberSnap.data()?['role'] as String?;
      if (currentRole != 'admin') {
        throw StateError('Only admins can be demoted.');
      }
      await memberRef.update({'role': 'member'});
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  Future<void> _ensureMemberCount(
    DocumentReference<Map<String, dynamic>> groupRef,
  ) async {
    final groupSnap = await groupRef.get();
    if (!groupSnap.exists) {
      return;
    }
    final data = groupSnap.data();
    if (data != null && data.containsKey('memberCount')) {
      return;
    }
    final membersSnap =
        await groupRef.collection(GroupCollections.members).get();
    await groupRef.set(
      {'memberCount': membersSnap.docs.length},
      SetOptions(merge: true),
    );
  }

  /// Update or create a [schedule] entry for [groupId].
  Future<void> updateSchedule({
    required String groupId,
    required GroupSchedule schedule,
  }) async {
    // First, write the schedule document. If this fails, bubble up the error.
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

    // Best-effort: attempt to notify members. Log failures but do not fail
    // the schedule update, since notifications can be restricted by rules.
    try {
      final members = await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.members)
          .get();

      for (final doc in members.docs) {
        final uid = doc.id;
        try {
          final notificationId = firestore
              .collection(NotificationCollections.users)
              .doc(uid)
              .collection(NotificationCollections.notifications)
              .doc()
              .id;
          final notification = AppNotification(
            id: notificationId,
            type: NotificationType.groupScheduleUpdate,
            timestamp: DateTime.now(),
            read: false,
          );
          await notificationService.addNotification(uid, notification);
        } catch (e, st) {
          await ErrorLogger.log(e, st);
          // continue notifying other members
        }
      }
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      // Do not rethrow: schedule has been updated successfully.
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

        final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
        for (var i = 0; i < missingUids.length; i += 10) {
          final batch = missingUids.sublist(
            i,
            i + 10 > missingUids.length ? missingUids.length : i + 10,
          );
          futures.add(firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: batch)
              .get());
        }

        final results = await Future.wait(futures);
        for (final query in results) {
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

  /// Stream of daily completion progress for members of [groupId].
  Stream<List<GroupMemberProgressData>> memberDailyCompletion(
    String groupId, {
    DateTime? date,
    String? includeUid,
  }) {
    final targetDate = date ?? DateTime.now();
    final dateId = _dateId(targetDate);

    final membersSnaps = firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.members)
        .snapshots()
        .handleError((e, st) {
      unawaited(ErrorLogger.log(e, st));
      throw e;
    });

    final logsSnaps = firestore
        .collection('read_logs')
        .doc(dateId)
        .collection('entries')
        .snapshots()
        .handleError((e, st) {
      unawaited(ErrorLogger.log(e, st));
      throw e;
    });

    return Stream<List<GroupMemberProgressData>>.multi((controller) {
      QuerySnapshot<Map<String, dynamic>>? latestMembers;
      QuerySnapshot<Map<String, dynamic>>? latestLogs;

      Future<void> emit() async {
        final members = latestMembers;
        final logs = latestLogs;
        if (members == null || logs == null) {
          return;
        }

        try {
          final progress =
              await _buildMemberDailyCompletion(members, logs, includeUid);
          controller.add(progress);
        } catch (e, st) {
          await ErrorLogger.log(e, st);
          controller.addError(e, st);
        }
      }

      final memberSub = membersSnaps.listen(
        (snap) {
          latestMembers = snap;
          unawaited(emit());
        },
        onError: controller.addError,
      );

      final logSub = logsSnaps.listen(
        (snap) {
          latestLogs = snap;
          unawaited(emit());
        },
        onError: controller.addError,
      );

      controller
        ..onListen = () {
          if (latestMembers != null && latestLogs != null) {
            unawaited(emit());
          }
        }
        ..onCancel = () {
          memberSub.cancel();
          logSub.cancel();
        };
    });
  }

  Future<List<GroupMemberProgressData>> _buildMemberDailyCompletion(
    QuerySnapshot<Map<String, dynamic>> membersSnap,
    QuerySnapshot<Map<String, dynamic>> logsSnap,
    String? includeUid,
  ) async {
    final order = <String>[];
    final providedNames = <String, String>{};
    final missingUids = <String>[];

    for (final doc in membersSnap.docs) {
      final data = doc.data();
      final uid = (data['uid'] as String?) ?? doc.id;
      if (uid.isEmpty) {
        continue;
      }
      order.add(uid);
      final name = data['name'] as String?;
      if (name != null && name.isNotEmpty) {
        providedNames[uid] = name;
      } else {
        missingUids.add(uid);
      }
    }

    // Ensure current user (admin/owner) appears even if not in members.
    if (includeUid != null &&
        includeUid.isNotEmpty &&
        !order.contains(includeUid)) {
      order.add(includeUid);
      missingUids.add(includeUid);
    }

    final resolvedNames = await _fetchUserNames(missingUids);
    final completedUids = logsSnap.docs.map((doc) => doc.id).toSet();

    return [
      for (final uid in order)
        GroupMemberProgressData(
          uid: uid,
          name: providedNames[uid] ?? resolvedNames[uid] ?? uid,
          completion: completedUids.contains(uid) ? 1.0 : 0.0,
        )
    ];
  }

  Future<Map<String, String>> _fetchUserNames(List<String> uids) async {
    if (uids.isEmpty) {
      return <String, String>{};
    }

    final uniqueUids = uids.toSet().toList();
    final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    for (var i = 0; i < uniqueUids.length; i += 10) {
      final end = i + 10 > uniqueUids.length ? uniqueUids.length : i + 10;
      final batch = uniqueUids.sublist(i, end);
      futures.add(firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: batch)
          .get());
    }

    final names = <String, String>{};
    if (futures.isEmpty) {
      return names;
    }

    final results = await Future.wait(futures);
    for (final query in results) {
      for (final user in query.docs) {
        final data = user.data();
        final userName = (data['name'] as String?)?.trim();
        final displayName = (data['displayName'] as String?)?.trim();
        final email = (data['email'] as String?)?.trim();
        String? chosen;
        if (userName != null && userName.isNotEmpty) {
          chosen = userName;
        } else if (displayName != null && displayName.isNotEmpty) {
          chosen = displayName;
        } else if (email != null && email.isNotEmpty) {
          final at = email.indexOf('@');
          chosen = at > 0 ? email.substring(0, at) : email;
        }
        if (chosen != null && chosen.isNotEmpty) {
          names[user.id] = chosen;
        }
      }
    }
    return names;
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

  /// Update the group's display name.
  Future<void> updateGroupName({
    required String groupId,
    required String name,
  }) async {
    try {
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .set({'name': name}, SetOptions(merge: true));
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }
}
