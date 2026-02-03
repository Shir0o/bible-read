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

  static Future<void> _safeLog(Object e, StackTrace? st) async {
    try {
      await ErrorLogger.log(e, st);
    } catch (_) {}
  }

  /// Create a new group owned by [ownerUid] with [name].
  ///
  /// Returns the id of the created group.
  Future<String> createGroup({
    required String ownerUid,
    required String name,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Group name cannot be empty');
    }
    try {
      final doc = firestore.collection(GroupCollections.groups).doc();
      await doc.set({
        'name': name.trim(),
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
        await _safeLog(e, st);
      }
      return doc.id;
    } catch (e, st) {
      await _safeLog(e, st);
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
        // Deterministic ID to avoid duplicates per requester per group.
        final notificationId = 'groupJoinRequest_${groupId}_$uid';
        final notification = AppNotification(
          id: notificationId,
          type: NotificationType.groupJoinRequest,
          fromUid: uid,
          senderUid: uid,
          groupId: groupId,
          message:
              name.isNotEmpty ? '$name requested to join your group' : null,
          timestamp: DateTime.now(),
          read: false,
        );
        await firestore
            .collection(NotificationCollections.users)
            .doc(ownerUid)
            .collection(NotificationCollections.notifications)
            .doc(notificationId)
            .set(notification.toFirestore(), SetOptions(merge: true));
      }
    } catch (e, st) {
      await _safeLog(e, st);
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
      await _safeLog(e, st);
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
      await _safeLog(e, st);
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

      // Cleanup user's progress summary and per-date entries (best-effort).
      try {
        await groupRef
            .collection('progressSummary')
            .doc('data')
            .collection('entries')
            .doc(uid)
            .delete();
      } catch (_) {}
      try {
        final dates = await groupRef.collection('progress').get();
        for (final d in dates.docs) {
          try {
            final entryRef = d.reference.collection('entries').doc(uid);
            final items = await entryRef.collection('items').get();
            for (final it in items.docs) {
              try {
                await it.reference.delete();
              } catch (_) {}
            }
            await entryRef.delete();
          } catch (_) {}
        }
      } catch (_) {}
    } catch (e, st) {
      await _safeLog(e, st);
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
      await _safeLog(e, st);
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
      await _safeLog(e, st);
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
      await _safeLog(e, st);
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
          await _safeLog(e, st);
          // continue notifying other members
        }
      }
    } catch (e, st) {
      await _safeLog(e, st);
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
      final groupRef =
          firestore.collection(GroupCollections.groups).doc(groupId);
      // Delete schedule doc
      await groupRef.collection(GroupCollections.schedule).doc(docId).delete();

      // Cleanup any progress entries for this date and update summaries.
      final dateRef = groupRef.collection('progress').doc(docId);
      final entries = await dateRef.collection('entries').get();
      for (final entry in entries.docs) {
        final uid = entry.id;
        final cnt = (entry.data()['count'] as num?)?.toInt() ?? 0;
        try {
          if (cnt > 0) {
            // Decrement cached total for this member.
            await groupRef
                .collection('progressSummary')
                .doc('data')
                .collection('entries')
                .doc(uid)
                .set({'completed': FieldValue.increment(-cnt)},
                    SetOptions(merge: true));
          }
          // Delete items and entry
          final items = await entry.reference.collection('items').get();
          for (final it in items.docs) {
            try {
              await it.reference.delete();
            } catch (_) {}
          }
          await entry.reference.delete();
        } catch (e, st) {
          await _safeLog(e, st);
        }
      }
      // Delete the progress date doc itself
      try {
        await dateRef.delete();
      } catch (_) {}
    } catch (e, st) {
      await _safeLog(e, st);
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
      await _safeLog(e, st);
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
            await _safeLog(e, st);
            controller.add(<Group>[]);
          }
        },
        onError: (e, st) async {
          await _safeLog(e, st);
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
          await _safeLog(e, st);
          memberGroups = <Group>[];
        }
        await emit();
      }

      Future<void> handleOwner(QuerySnapshot<Map<String, dynamic>> snap) async {
        try {
          ownerGroups = snap.docs.map(Group.fromFirestore).toList();
        } catch (e, st) {
          await _safeLog(e, st);
          ownerGroups = <Group>[];
        }
        await emit();
      }

      final sub1 = memberSnaps.listen(
        (snap) => unawaited(handleMember(snap)),
        onError: (e, st) async {
          await _safeLog(e, st);
          memberGroups = <Group>[];
          await emit();
        },
      );
      final sub2 = ownerSnaps.listen(
        (snap) => unawaited(handleOwner(snap)),
        onError: (e, st) async {
          await _safeLog(e, st);
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
      unawaited(_safeLog(e, st));
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
        await _safeLog(e, st);
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
      unawaited(_safeLog(e, st));
      throw e;
    });

    // Group-scoped per-date entries marking completion
    final progressSnaps = firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection('progress')
        .doc(dateId)
        .collection('entries')
        .snapshots();

    return Stream<List<GroupMemberProgressData>>.multi((controller) {
      QuerySnapshot<Map<String, dynamic>>? latestMembers;
      QuerySnapshot<Map<String, dynamic>>? latestProgress;
      bool progressDenied = false;

      Future<void> emit() async {
        final members = latestMembers;
        final progress = latestProgress;
        if (members == null) return;

        try {
          if (progress == null && progressDenied) {
            // Treat as no completed entries visible; emit zeros for all members.
            final order = <String>[];
            final providedNames = <String, String>{};
            for (final doc in members.docs) {
              final data = doc.data();
              final uid = (data['uid'] as String?) ?? doc.id;
              if (uid.isEmpty) continue;
              order.add(uid);
              final name = data['name'] as String?;
              if (name != null && name.isNotEmpty) {
                providedNames[uid] = name;
              }
            }
            final resolved = await _fetchUserInfos(
                order.where((uid) => !providedNames.containsKey(uid)).toList());
            controller.add([
              for (final uid in order)
                GroupMemberProgressData(
                  uid: uid,
                  name: providedNames[uid] ?? resolved[uid]?.name ?? uid,
                  photoUrl: resolved[uid]?.photoUrl,
                  completion: 0.0,
                )
            ]);
            return;
          }
          if (progress == null) return;
          final list = await _buildMemberDailyCompletion(
              members, progress, includeUid,
              groupId: groupId, date: targetDate);
          controller.add(list);
        } catch (e, st) {
          await _safeLog(e, st);
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

      final progSub = progressSnaps.listen(
        (snap) {
          latestProgress = snap;
          progressDenied = false;
          unawaited(emit());
        },
        onError: (e, st) async {
          await _safeLog(e, st);
          progressDenied = true;
          latestProgress = null;
          unawaited(emit());
        },
      );

      controller
        ..onListen = () {
          if (latestMembers != null &&
              (latestProgress != null || progressDenied)) {
            unawaited(emit());
          }
        }
        ..onCancel = () {
          memberSub.cancel();
          progSub.cancel();
        };
    });
  }

  /// Stream of overall completion across all scheduled chapters for the group.
  /// Completion is computed as sum(checked items) / sum(total scheduled items).
  Stream<List<GroupMemberProgressData>> memberOverallCompletion(
    String groupId, {
    String? includeUid,
  }) {
    final membersSnaps = firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.members)
        .snapshots()
        .handleError((e, st) {
      unawaited(_safeLog(e, st));
      throw e;
    });

    final scheduleSnaps = firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.schedule)
        .snapshots()
        .handleError((e, st) {
      unawaited(_safeLog(e, st));
      throw e;
    });

    final entriesSnaps = firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection('progressSummary')
        .doc('data')
        .collection('entries')
        .snapshots()
        .handleError((e, st) {
      unawaited(_safeLog(e, st));
      throw e;
    });

    return Stream<List<GroupMemberProgressData>>.multi((controller) {
      QuerySnapshot<Map<String, dynamic>>? latestMembers;
      QuerySnapshot<Map<String, dynamic>>? latestSchedule;
      QuerySnapshot<Map<String, dynamic>>? latestEntries;

      Future<void> emit() async {
        if (latestMembers == null ||
            latestSchedule == null ||
            latestEntries == null) {
          return;
        }
        try {
          // Build order and names similar to daily completion.
          final order = <String>[];
          final providedNames = <String, String>{};
          final missingUids = <String>[];
          for (final doc in latestMembers!.docs) {
            final data = doc.data();
            final uid = (data['uid'] as String?) ?? doc.id;
            if (uid.isEmpty) continue;
            order.add(uid);
            final name = data['name'] as String?;
            if (name != null && name.isNotEmpty) {
              providedNames[uid] = name;
            } else {
              missingUids.add(uid);
            }
          }

          // Include owner if missing
          try {
            final groupSnap = await firestore
                .collection(GroupCollections.groups)
                .doc(groupId)
                .get();
            final ownerUid = groupSnap.data()?['ownerUid'] as String?;
            if (ownerUid != null &&
                ownerUid.isNotEmpty &&
                !order.contains(ownerUid)) {
              order.add(ownerUid);
              missingUids.add(ownerUid);
            }
          } catch (e, st) {
            await _safeLog(e, st);
          }

          if (includeUid != null &&
              includeUid.isNotEmpty &&
              !order.contains(includeUid)) {
            order.add(includeUid);
            missingUids.add(includeUid);
          }

          final resolvedNames = await _fetchUserInfos(missingUids);

          // Total scheduled items = sum of all chapter counts.
          int totalItems = 0;
          for (final doc in latestSchedule!.docs) {
            final ch = (doc.data()['chapters'] as List?)?.length ?? 0;
            totalItems += ch;
          }
          if (totalItems == 0) {
            controller.add([
              for (final uid in order)
                GroupMemberProgressData(
                  uid: uid,
                  name: providedNames[uid] ?? resolvedNames[uid]?.name ?? uid,
                  photoUrl: resolvedNames[uid]?.photoUrl,
                  completion: 0.0,
                )
            ]);
            return;
          }

          // Sum counts per uid from entries.
          final counts = <String, int>{};
          for (final e in latestEntries!.docs) {
            final data = e.data();
            final uid = e.id;
            if (uid.isEmpty) continue;
            final c = (data['completed'] as num?)?.toInt();
            if (c == null) continue;
            counts[uid] = c;
          }

          controller.add([
            for (final uid in order)
              GroupMemberProgressData(
                uid: uid,
                name: providedNames[uid] ?? resolvedNames[uid]?.name ?? uid,
                photoUrl: resolvedNames[uid]?.photoUrl,
                completion: ((counts[uid] ?? 0) / totalItems).clamp(0.0, 1.0),
              )
          ]);
        } catch (e, st) {
          await _safeLog(e, st);
          controller.addError(e, st);
        }
      }

      final subMembers = membersSnaps.listen((snap) {
        latestMembers = snap;
        unawaited(emit());
      }, onError: controller.addError);
      final subSched = scheduleSnaps.listen((snap) {
        latestSchedule = snap;
        unawaited(emit());
      }, onError: controller.addError);
      final subEntries = entriesSnaps.listen((snap) {
        latestEntries = snap;
        unawaited(emit());
      }, onError: controller.addError);

      controller.onCancel = () {
        subMembers.cancel();
        subSched.cancel();
        subEntries.cancel();
      };
    });
  }

  Future<List<GroupMemberProgressData>> _buildMemberDailyCompletion(
    QuerySnapshot<Map<String, dynamic>> membersSnap,
    QuerySnapshot<Map<String, dynamic>> progressSnap,
    String? includeUid, {
    required String groupId,
    required DateTime date,
  }) async {
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

    // Always include the group owner in the member list even if no
    // membership document exists (for older data).
    try {
      final groupSnap = await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .get();
      final ownerUid = groupSnap.data()?['ownerUid'] as String?;
      if (ownerUid != null &&
          ownerUid.isNotEmpty &&
          !order.contains(ownerUid)) {
        order.add(ownerUid);
        missingUids.add(ownerUid);
      }
    } catch (e, st) {
      await _safeLog(e, st);
    }

    // Ensure current user (admin/owner) appears even if not in members.
    if (includeUid != null &&
        includeUid.isNotEmpty &&
        !order.contains(includeUid)) {
      order.add(includeUid);
      missingUids.add(includeUid);
    }

    final resolvedNames = await _fetchUserInfos(missingUids);

    // Determine total schedule items (chapters) for the date.
    final dateId = _dateId(date);
    final schedDoc = await firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.schedule)
        .doc(dateId)
        .get();
    final chapters = (schedDoc.data()?['chapters'] as List?)?.length ?? 0;
    final totalItems = chapters;
    if (totalItems == 0) {
      return [
        for (final uid in order)
          GroupMemberProgressData(
            uid: uid,
            name: providedNames[uid] ?? resolvedNames[uid]?.name ?? uid,
            photoUrl: resolvedNames[uid]?.photoUrl,
            completion: 0.0,
          )
      ];
    }

    // Compute completion as itemsChecked / totalItems.
    // Backwards compatibility: if an entry exists but has no items, treat as 100%.
    final futures = <Future<double>>[];
    for (final uid in order) {
      futures.add(() async {
        if (totalItems == 0) return 0.0;
        try {
          final itemsSnap = await firestore
              .collection(GroupCollections.groups)
              .doc(groupId)
              .collection('progress')
              .doc(dateId)
              .collection('entries')
              .doc(uid)
              .collection('items')
              .get();
          final count = itemsSnap.docs.length;
          return (count / totalItems).clamp(0.0, 1.0);
        } catch (_) {
          // If we cannot read items (permissions or missing), treat as 0%.
          return 0.0;
        }
      }());
    }
    final completions = await Future.wait(futures);
    return [
      for (var i = 0; i < order.length; i++)
        GroupMemberProgressData(
          uid: order[i],
          name: providedNames[order[i]] ?? resolvedNames[order[i]]?.name ?? order[i],
          photoUrl: resolvedNames[order[i]]?.photoUrl,
          completion: completions[i],
        )
    ];
  }

  Future<Map<String, _UserInfo>> _fetchUserInfos(List<String> uids) async {
    if (uids.isEmpty) {
      return <String, _UserInfo>{};
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

    final infos = <String, _UserInfo>{};
    if (futures.isEmpty) {
      return infos;
    }

    final results = await Future.wait(futures);
    for (final query in results) {
      for (final user in query.docs) {
        final data = user.data();
        final userName = (data['name'] as String?)?.trim();
        final displayName = (data['displayName'] as String?)?.trim();
        final email = (data['email'] as String?)?.trim();
        final photoUrl = (data['photoURL'] as String?)?.trim();
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
          infos[user.id] = _UserInfo(chosen, photoUrl);
        }
      }
    }
    return infos;
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
      unawaited(_safeLog(e, st));
      throw e;
    });
    return snaps.asyncMap((snap) async {
      try {
        return snap.docs.map(GroupSchedule.fromFirestore).toList();
      } catch (e, st) {
        await _safeLog(e, st);
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
      await _safeLog(e, st);
      rethrow;
    }
  }

  /// Permanently delete a group and its subcollections. Only the owner should
  /// call this. Rules enforce permissions; we also verify on the client.
  Future<void> deleteGroup({
    required String groupId,
    required String ownerUid,
  }) async {
    final groupRef = firestore.collection(GroupCollections.groups).doc(groupId);
    try {
      final snap = await groupRef.get();
      final data = snap.data();
      if (data == null || data['ownerUid'] != ownerUid) {
        throw StateError('Only the group owner can delete this group.');
      }

      // Delete members
      final members = await groupRef.collection(GroupCollections.members).get();
      for (final doc in members.docs) {
        try {
          await doc.reference.delete();
        } catch (_) {}
      }

      // Delete schedule
      final sched = await groupRef.collection(GroupCollections.schedule).get();
      for (final doc in sched.docs) {
        try {
          await doc.reference.delete();
        } catch (_) {}
      }

      // Delete join requests
      final requests =
          await groupRef.collection(GroupCollections.joinRequests).get();
      for (final doc in requests.docs) {
        try {
          await doc.reference.delete();
        } catch (_) {}
      }

      // Delete progress entries (progress/{dateId}/entries/* and date docs)
      final progressDates = await groupRef.collection('progress').get();
      for (final dateDoc in progressDates.docs) {
        try {
          final entries = await dateDoc.reference.collection('entries').get();
          for (final entry in entries.docs) {
            try {
              await entry.reference.delete();
            } catch (_) {}
          }
          // Delete the date document itself
          await dateDoc.reference.delete();
        } catch (_) {}
      }

      // Finally delete the group document
      await groupRef.delete();
    } catch (e, st) {
      await _safeLog(e, st);
      rethrow;
    }
  }

  /// Recalculate and persist the overall completed chapter count for [uid]
  /// within [groupId] by summing per-day entry item counts. Also backfills the
  /// per-day 'count' field when missing.
  Future<void> recalcProgressForUserInGroup({
    required String groupId,
    required String uid,
  }) async {
    try {
      final groupRef =
          firestore.collection(GroupCollections.groups).doc(groupId);
      final groupSnap = await groupRef.get();
      if (!groupSnap.exists) return;
      final ownerUid = groupSnap.data()?['ownerUid'] as String?;
      final isOwner = ownerUid == uid;

      // Ensure user is a member or owner before proceeding.
      final memberSnap =
          await groupRef.collection(GroupCollections.members).doc(uid).get();
      if (!memberSnap.exists && !isOwner) return;

      final progressDates = await groupRef.collection('progress').get();
      int total = 0;
      for (final dateDoc in progressDates.docs) {
        try {
          final entryRef = dateDoc.reference.collection('entries').doc(uid);
          final entrySnap = await entryRef.get();
          if (!entrySnap.exists) continue;
          int? count = (entrySnap.data()?['count'] as num?)?.toInt();
          if (count == null) {
            final itemsSnap = await entryRef.collection('items').get();
            count = itemsSnap.docs.length;
            try {
              await entryRef.set({'count': count}, SetOptions(merge: true));
            } catch (_) {}
          }
          total += count;
        } catch (e, st) {
          await _safeLog(e, st);
        }
      }

      final summaryRef = groupRef
          .collection('progressSummary')
          .doc('data')
          .collection('entries')
          .doc(uid);
      await summaryRef.set({'completed': total}, SetOptions(merge: true));
    } catch (e, st) {
      await _safeLog(e, st);
    }
  }

  /// Recalculate progress summaries for all groups the user belongs to or owns.
  Future<void> fixMemberProgressSummariesForUser(String uid) async {
    try {
      final groups = <String, Group>{};

      // 1. Groups where user is a member
      final memberSnaps = await firestore
          .collectionGroup(GroupCollections.members)
          .where('uid', isEqualTo: uid)
          .get();

      final memberGroupFutures = memberSnaps.docs
          .map((doc) => doc.reference.parent.parent)
          .whereType<DocumentReference<Map<String, dynamic>>>()
          .map((parent) => parent.get())
          .toList();
      final memberGroupDocs = await Future.wait(memberGroupFutures);
      for (final doc in memberGroupDocs) {
        if (doc.exists) {
          final g = Group.fromFirestore(doc);
          groups[g.id] = g;
        }
      }

      // 2. Groups owned by user
      final ownerSnaps = await firestore
          .collection(GroupCollections.groups)
          .where('ownerUid', isEqualTo: uid)
          .get();
      for (final doc in ownerSnaps.docs) {
        final g = Group.fromFirestore(doc);
        groups[g.id] = g;
      }

      for (final g in groups.values) {
        await recalcProgressForUserInGroup(groupId: g.id, uid: uid);
      }
    } catch (e, st) {
      await _safeLog(e, st);
    }
  }
}
class _UserInfo {
  final String name;
  final String? photoUrl;
  _UserInfo(this.name, this.photoUrl);
}
