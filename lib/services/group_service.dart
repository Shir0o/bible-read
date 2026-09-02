import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';
import '../models/group_member_progress.dart';
import '../models/group_plan_config.dart';
import '../models/group_schedule.dart';
import '../models/group.dart';
import '../models/group_invite.dart';
import '../models/group_member_role.dart';
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

  /// Sub-collection containing invitations to join.
  static const String invites = 'invites';
}

/// Provides helper methods for managing reading groups.
class GroupService {
  /// Writes per batched commit. Firestore's hard cap is 500; the headroom
  /// leaves room for a batch to carry an extra write alongside its documents.
  static const int _writeBatchSize = 450;

  /// Firestore instance used for database operations.
  final FirebaseFirestore firestore;

  /// Service for writing notification documents.
  final NotificationService notificationService;

  /// Creates a [GroupService] using [FirebaseFirestore.instance] by default.
  GroupService({
    FirebaseFirestore? firestore,
    NotificationService? notificationService,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        notificationService = notificationService ??
            NotificationService(
              firestore: firestore ?? FirebaseFirestore.instance,
            );

  static Future<void> _safeLog(Object e, StackTrace? st) async {
    try {
      await ErrorLogger.log(e, st);
    } catch (_) {}
  }

  static String? _resolveDisplayName(Map<String, dynamic> data) {
    final n = (data['name'] as String?)?.trim();
    final dn = (data['displayName'] as String?)?.trim();
    final em = (data['email'] as String?)?.trim();
    if (n != null && n.isNotEmpty) return n;
    if (dn != null && dn.isNotEmpty) return dn;
    if (em != null && em.isNotEmpty) {
      final at = em.indexOf('@');
      return at > 0 ? em.substring(0, at) : em;
    }
    return null;
  }

  /// Create a new group owned by [ownerUid] with [name].
  ///
  /// Returns the id of the created group.
  Future<String> createGroup({
    required String ownerUid,
    required String name,
    bool isPublic = false,
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
        'isPublic': isPublic,
      });
      await doc.collection(GroupCollections.members).doc(ownerUid).set({
        'uid': ownerUid,
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
      });
      // Best-effort: populate owner's display name and photo on member record.
      try {
        final userSnap =
            await firestore.collection('users').doc(ownerUid).get();
        final data = userSnap.data();
        if (data != null) {
          final chosen = _resolveDisplayName(data);
          final photoUrl = (data['photoURL'] as String?)?.trim();
          final updates = <String, dynamic>{};
          if (chosen != null) updates['name'] = chosen;
          if (photoUrl != null && photoUrl.isNotEmpty) {
            updates['photoUrl'] = photoUrl;
          }
          if (updates.isNotEmpty) {
            await doc
                .collection(GroupCollections.members)
                .doc(ownerUid)
                .set(updates, SetOptions(merge: true));
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
  /// If the group is public, it joins directly. Otherwise, it creates a join
  /// request for the group owner to approve.
  Future<void> joinGroup({
    required String groupId,
    required String uid,
    required String name,
    String? photoUrl,
    bool? isPublic,
  }) async {
    try {
      bool public = isPublic ?? false;
      if (isPublic == null) {
        final groupSnap = await firestore
            .collection(GroupCollections.groups)
            .doc(groupId)
            .get();
        public = groupSnap.data()?['isPublic'] as bool? ?? false;
      }

      if (public) {
        return joinGroupDirectly(
          groupId: groupId,
          uid: uid,
          name: name,
          photoUrl: photoUrl,
        );
      } else {
        return requestJoin(
          groupId: groupId,
          uid: uid,
          name: name,
          photoUrl: photoUrl,
        );
      }
    } catch (e, st) {
      await _safeLog(e, st);
      rethrow;
    }
  }

  /// Directly add [uid] to the group with [groupId] without a join request.
  ///
  /// Typically used for public groups or when an invite is accepted.
  Future<void> joinGroupDirectly({
    required String groupId,
    required String uid,
    required String name,
    String? photoUrl,
  }) async {
    try {
      final groupRef =
          firestore.collection(GroupCollections.groups).doc(groupId);
      final groupSnap = await groupRef.get();
      if (!groupSnap.exists) {
        throw StateError('Group does not exist');
      }

      final memberRef = groupRef.collection(GroupCollections.members).doc(uid);
      final memberSnap = await memberRef.get();

      if (memberSnap.exists) {
        return; // Already a member
      }

      final data = <String, dynamic>{
        'uid': uid,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      };
      if (name.isNotEmpty) {
        data['name'] = name;
      }
      if (photoUrl != null && photoUrl.isNotEmpty) {
        data['photoUrl'] = photoUrl;
      }

      final batch = firestore.batch();
      batch.set(memberRef, data, SetOptions(merge: true));
      await _ensureMemberCount(groupRef);
      batch.update(groupRef, {'memberCount': FieldValue.increment(1)});

      // Also delete any existing join request if they had one
      batch.delete(groupRef.collection(GroupCollections.joinRequests).doc(uid));

      await batch.commit();
    } catch (e, st) {
      await _safeLog(e, st);
      rethrow;
    }
  }

  /// Create a join request for [uid] on [groupId].
  Future<void> requestJoin({
    required String groupId,
    required String uid,
    required String name,
    String? photoUrl,
  }) async {
    try {
      final groupSnap = await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .get();

      if (!groupSnap.exists) {
        throw StateError('Group does not exist');
      }

      final memberSnap = await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.members)
          .doc(uid)
          .get();
      if (memberSnap.exists) {
        return;
      }

      final data = <String, dynamic>{
        'uid': uid,
        'name': name,
        'requestedAt': FieldValue.serverTimestamp(),
      };
      if (photoUrl != null && photoUrl.isNotEmpty) {
        data['photoUrl'] = photoUrl;
      }

      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.joinRequests)
          .doc(uid)
          .set(data);

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

  /// Send an invitation to [recipientUid] to join [groupId].
  Future<void> sendGroupInvite({
    required String groupId,
    required String groupName,
    required String senderUid,
    required String senderName,
    required String recipientUid,
  }) async {
    try {
      final groupRef =
          firestore.collection(GroupCollections.groups).doc(groupId);
      final groupSnap = await groupRef.get();
      if (!groupSnap.exists) {
        throw StateError('Group does not exist');
      }

      if (recipientUid == senderUid) {
        throw StateError('Cannot invite yourself to a group.');
      }

      final ownerUid = groupSnap.data()?['ownerUid'] as String?;
      if (senderUid != ownerUid) {
        final senderMemberSnap = await groupRef
            .collection(GroupCollections.members)
            .doc(senderUid)
            .get();
        final senderRole = senderMemberSnap.data()?['role'] as String?;
        if (senderRole != 'admin' && senderRole != 'owner') {
          throw StateError('Only group owners and admins can invite members.');
        }
      }

      final recipientMemberSnap = await groupRef
          .collection(GroupCollections.members)
          .doc(recipientUid)
          .get();
      if (recipientMemberSnap.exists) {
        throw StateError('Cannot invite an existing group member.');
      }

      final invite = GroupInvite(
        id: '', // Firestore will assign
        groupId: groupId,
        groupName: groupName,
        senderUid: senderUid,
        senderName: senderName,
        recipientUid: recipientUid,
        timestamp: DateTime.now(),
      );

      // Store in group's invites collection
      await groupRef
          .collection(GroupCollections.invites)
          .doc(recipientUid)
          .set(invite.toFirestore());

      // Send notification to recipient
      final notificationId = 'groupInvite_${groupId}_$senderUid';
      final notification = AppNotification(
        id: notificationId,
        type: NotificationType.groupInvite,
        fromUid: senderUid,
        senderUid: senderUid,
        groupId: groupId,
        message: '$senderName invited you to join $groupName',
        timestamp: DateTime.now(),
        read: false,
      );

      await firestore
          .collection(NotificationCollections.users)
          .doc(recipientUid)
          .collection(NotificationCollections.notifications)
          .doc(notificationId)
          .set(notification.toFirestore(), SetOptions(merge: true));
    } catch (e, st) {
      await _safeLog(e, st);
      rethrow;
    }
  }

  /// Stream of invitations for the user with [uid].
  Stream<List<GroupInvite>> userInvites(String uid) {
    return firestore
        .collectionGroup(GroupCollections.invites)
        .where('recipientUid', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs.map(GroupInvite.fromFirestore).toList());
  }

  /// Respond to a group invitation.
  Future<void> respondToGroupInvite({
    required String groupId,
    required String uid,
    required String name,
    String? photoUrl,
    required bool accept,
  }) async {
    try {
      final groupRef =
          firestore.collection(GroupCollections.groups).doc(groupId);
      final inviteRef = groupRef.collection(GroupCollections.invites).doc(uid);

      if (accept) {
        final inviteSnap = await inviteRef.get();
        if (!inviteSnap.exists) {
          throw StateError('Cannot accept a missing group invite.');
        }
        await joinGroupDirectly(
          groupId: groupId,
          uid: uid,
          name: name,
          photoUrl: photoUrl,
        );
      }
      await inviteRef.delete();

      // Cleanup notifications
      final snaps = await firestore
          .collection(NotificationCollections.users)
          .doc(uid)
          .collection(NotificationCollections.notifications)
          .where('groupId', isEqualTo: groupId)
          .where('type', isEqualTo: NotificationType.groupInvite.name)
          .get();

      final batch = firestore.batch();
      for (final doc in snaps.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
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
      if (!requestSnap.exists) {
        throw StateError('Cannot approve a missing join request.');
      }
      final name = requestSnap.data()?['name'] as String?;
      final photoUrl = requestSnap.data()?['photoUrl'] as String?;

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
      if (photoUrl != null && photoUrl.isNotEmpty) {
        data['photoUrl'] = photoUrl;
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
        // ⚡ Bolt: Use a hybrid approach for cleanup. Start with collectionGroup for efficiency.
        final entriesSnap = await firestore
            .collectionGroup('entries')
            .where('uid', isEqualTo: uid)
            .where('groupId', isEqualTo: groupId)
            .get();

        final foundEntryRefs = entriesSnap.docs.map((d) => d.reference).toSet();
        final allDateSnaps = await groupRef.collection('progress').get();

        final missingDates = allDateSnaps.docs.where((dateDoc) {
          final entryRef = dateDoc.reference.collection('entries').doc(uid);
          return !foundEntryRefs.contains(entryRef);
        }).toList();

        final fallbackSnaps = <DocumentSnapshot<Map<String, dynamic>>>[];
        if (missingDates.isNotEmpty) {
          const chunkSize = 30;
          for (var i = 0; i < missingDates.length; i += chunkSize) {
            final chunk = missingDates.sublist(
              i,
              i + chunkSize > missingDates.length
                  ? missingDates.length
                  : i + chunkSize,
            );
            final results = await Future.wait(
              chunk.map(
                (d) => d.reference
                    .collection('entries')
                    .doc(uid)
                    .get()
                    .then<DocumentSnapshot<Map<String, dynamic>>?>((s) => s)
                    .catchError((Object e, StackTrace st) {
                  _safeLog(e, st);
                  return null;
                }),
              ),
            );
            fallbackSnaps.addAll(
              results.whereType<DocumentSnapshot<Map<String, dynamic>>>(),
            );
          }
        }

        final allRelevantEntrySnaps = [
          ...entriesSnap.docs,
          ...fallbackSnaps.where((s) => s.exists),
        ];

        final refsToDelete = <DocumentReference>[];
        for (final entrySnap in allRelevantEntrySnaps) {
          refsToDelete.add(entrySnap.reference);
        }

        // Fetch items for all found entries in parallel chunks.
        if (allRelevantEntrySnaps.isNotEmpty) {
          const chunkSize = 30;
          for (var i = 0; i < allRelevantEntrySnaps.length; i += chunkSize) {
            final chunk = allRelevantEntrySnaps.sublist(
              i,
              i + chunkSize > allRelevantEntrySnaps.length
                  ? allRelevantEntrySnaps.length
                  : i + chunkSize,
            );
            final itemSnaps = await Future.wait(
              chunk.map((d) => d.reference.collection('items').get()),
            );
            for (final snap in itemSnaps) {
              for (final doc in snap.docs) {
                refsToDelete.add(doc.reference);
              }
            }
          }
        }

        if (refsToDelete.isNotEmpty) {
          await _deleteInBatches(refsToDelete);
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
    await groupRef.set({
      'memberCount': membersSnap.docs.length,
    }, SetOptions(merge: true));
  }

  /// Update or create a [schedule] entry for [groupId].
  Future<void> updateSchedule({
    required String groupId,
    required GroupSchedule schedule,
  }) async {
    // First, write the schedule document. If this fails, bubble up the error.
    try {
      final docId = dateId(schedule.date);
      final utcDate = DateTime.utc(
        schedule.date.year,
        schedule.date.month,
        schedule.date.day,
      );
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

      // ⚡ Bolt: Use Future.wait to parallelize sending schedule update
      // notifications instead of waiting for each one sequentially.
      await Future.wait(
        members.docs.map((doc) async {
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
        }),
      );
    } catch (e, st) {
      await _safeLog(e, st);
      // Do not rethrow: schedule has been updated successfully.
    }
  }

  /// Update multiple schedule entries for [groupId] using batched writes.
  ///
  /// Split across several commits so a long plan stays under Firestore's
  /// 500-writes-per-batch cap — reading the whole Bible at one chapter a day is
  /// 1,189 days, which a single batch cannot carry.
  Future<void> updateScheduleBatch({
    required String groupId,
    required List<GroupSchedule> schedules,
  }) async {
    if (schedules.isEmpty) return;
    try {
      final scheduleRef = firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.schedule);

      for (var i = 0; i < schedules.length; i += _writeBatchSize) {
        final batch = firestore.batch();
        final end = (i + _writeBatchSize < schedules.length)
            ? i + _writeBatchSize
            : schedules.length;
        for (var j = i; j < end; j++) {
          final schedule = schedules[j];
          batch.set(
            scheduleRef.doc(dateId(schedule.date)),
            schedule.toFirestore(),
          );
        }
        await batch.commit();
      }
    } catch (e, st) {
      await _safeLog(e, st);
      rethrow;
    }
  }

  /// Persist the configuration a group's schedule was generated from.
  ///
  /// Kept alongside the materialised schedule so the plan can be reopened for
  /// editing exactly as it was set — the schedule alone does not record where
  /// the plan started or which days were set by hand.
  Future<void> updatePlanConfig({
    required String groupId,
    required GroupPlanDraft config,
  }) async {
    try {
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .set({'planConfig': config.toFirestore()}, SetOptions(merge: true));
    } catch (e, st) {
      await _safeLog(e, st);
      rethrow;
    }
  }

  /// Delete the schedule entries on [dates] for [groupId], along with the
  /// progress recorded against them.
  ///
  /// Used when regenerating a plan leaves days that no longer belong to it.
  Future<void> deleteScheduleDays({
    required String groupId,
    required Iterable<DateTime> dates,
  }) async {
    for (final date in dates) {
      await deleteSchedule(groupId: groupId, date: date);
    }
  }

  /// Delete the schedule entry on [date] for [groupId].
  Future<void> deleteSchedule({
    required String groupId,
    required DateTime date,
  }) async {
    try {
      final docId = dateId(date);
      final groupRef =
          firestore.collection(GroupCollections.groups).doc(groupId);
      // Delete schedule doc
      await groupRef.collection(GroupCollections.schedule).doc(docId).delete();

      // Cleanup any progress entries for this date and update summaries.
      final dateRef = groupRef.collection('progress').doc(docId);
      final entries = await dateRef.collection('entries').get();

      // ⚡ Bolt: Use Future.wait to parallelize deleting progress entries
      // instead of deleting them sequentially.
      await Future.wait(
        entries.docs.map((entry) async {
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
                  .set({
                'completed': FieldValue.increment(-cnt),
                'uid': uid,
              }, SetOptions(merge: true));
            }
            // Delete items and entry
            final items = await entry.reference.collection('items').get();
            await Future.wait(
              items.docs.map((it) async {
                try {
                  await it.reference.delete();
                } catch (_) {}
              }),
            );
            await entry.reference.delete();
          } catch (e, st) {
            await _safeLog(e, st);
          }
        }),
      );
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
      final docId = dateId(DateTime.now());
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

  /// Firestore document id for a schedule or progress date: `YYYY-MM-DD`.
  ///
  /// Zero-padded, so ids sort lexicographically in date order. Callers building
  /// date keys must use this rather than interpolating the parts themselves.
  static String dateId(DateTime date) {
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
          if (controller.isClosed) return;
          try {
            controller.add(snap.docs.map(Group.fromFirestore).toList());
          } catch (e, st) {
            await _safeLog(e, st);
            if (!controller.isClosed) controller.add(<Group>[]);
          }
        },
        onError: (e, st) async {
          await _safeLog(e, st);
          if (!controller.isClosed) controller.add(<Group>[]);
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

    final joinRequestSnaps = firestore
        .collectionGroup(GroupCollections.joinRequests)
        .where('uid', isEqualTo: uid)
        .snapshots();

    return Stream<List<Group>>.multi((controller) {
      var memberGroups = <Group>[];
      var ownerGroups = <Group>[];
      var pendingGroups = <Group>[];

      Future<void> emit() async {
        if (controller.isClosed) return;
        final merged = <String, Group>{};
        for (final g in memberGroups) {
          merged[g.id] = g;
        }
        for (final g in ownerGroups) {
          merged[g.id] = g;
        }
        for (final g in pendingGroups) {
          merged[g.id] = g;
        }
        if (!controller.isClosed) {
          controller.add(merged.values.toList());
        }
      }

      Future<void> handleMember(
        QuerySnapshot<Map<String, dynamic>> snap,
      ) async {
        try {
          final ids = snap.docs
              .map((doc) => doc.reference.parent.parent?.id)
              .whereType<String>()
              .toList();
          memberGroups = await _fetchGroupsByIds(ids);
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

      Future<void> handleJoinRequest(
        QuerySnapshot<Map<String, dynamic>> snap,
      ) async {
        try {
          final ids = snap.docs
              .map((doc) => doc.reference.parent.parent?.id)
              .whereType<String>()
              .toList();
          pendingGroups = await _fetchGroupsByIds(ids);
        } catch (e, st) {
          await _safeLog(e, st);
          pendingGroups = <Group>[];
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
      final sub3 = joinRequestSnaps.listen(
        (snap) => unawaited(handleJoinRequest(snap)),
        onError: (e, st) async {
          await _safeLog(e, st);
          pendingGroups = <Group>[];
          await emit();
        },
      );

      controller.onCancel = () {
        sub1.cancel();
        sub2.cancel();
        sub3.cancel();
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

        // ⚡ Bolt: Fetch missing users in parallel to reduce N+1 queries.
        // Use mapped gets to avoid limit constraints and reduce query payload size.
        final chunkedFutures =
            <Future<List<DocumentSnapshot<Map<String, dynamic>>>>>[];
        for (var i = 0; i < missingUids.length; i += 30) {
          final batch = missingUids.sublist(
            i,
            i + 30 > missingUids.length ? missingUids.length : i + 30,
          );
          chunkedFutures.add(
            Future.wait(
              batch.map((uid) => firestore.collection('users').doc(uid).get()),
            ),
          );
        }

        final results = await Future.wait(chunkedFutures);
        for (final chunkResults in results) {
          for (final user in chunkResults) {
            if (!user.exists) continue;
            final chosen = _resolveDisplayName(user.data()!);
            if (chosen != null) {
              names.add(chosen);
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
    final dateId = GroupService.dateId(targetDate);

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
        if (controller.isClosed) return;
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
              order.where((uid) => !providedNames.containsKey(uid)).toList(),
            );
            if (controller.isClosed) return;
            controller.add([
              for (final uid in order)
                GroupMemberProgressData(
                  uid: uid,
                  name: providedNames[uid] ?? resolved[uid]?.name ?? uid,
                  photoUrl: resolved[uid]?.photoUrl,
                  completion: 0.0,
                ),
            ]);
            return;
          }
          if (progress == null) return;
          final list = await _buildMemberDailyCompletion(
            members,
            progress,
            includeUid,
            groupId: groupId,
            date: targetDate,
          );
          if (!controller.isClosed) {
            controller.add(list);
          }
        } catch (e, st) {
          await _safeLog(e, st);
          if (!controller.isClosed) {
            controller.addError(e, st);
          }
        }
      }

      final memberSub = membersSnaps.listen(
        (snap) {
          latestMembers = snap;
          unawaited(emit());
        },
        onError: (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        },
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
          final providedPhotos = <String, String>{};
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
            final photoUrl = data['photoUrl'] as String?;
            if (photoUrl != null && photoUrl.isNotEmpty) {
              providedPhotos[uid] = photoUrl;
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

          final resolvedInfos = await _fetchUserInfos(missingUids);

          // Total scheduled items = sum of all chapter counts.
          int totalItems = 0;
          for (final doc in latestSchedule!.docs) {
            final ch = (doc.data()['chapters'] as List?)?.length ?? 0;
            totalItems += ch;
          }
          if (totalItems == 0) {
            if (!controller.isClosed) {
              controller.add([
                for (final uid in order)
                  GroupMemberProgressData(
                    uid: uid,
                    name: providedNames[uid] ?? resolvedInfos[uid]?.name ?? uid,
                    photoUrl:
                        providedPhotos[uid] ?? resolvedInfos[uid]?.photoUrl,
                    completion: 0.0,
                  ),
              ]);
            }
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

          if (!controller.isClosed) {
            controller.add([
              for (final uid in order)
                GroupMemberProgressData(
                  uid: uid,
                  name: providedNames[uid] ?? resolvedInfos[uid]?.name ?? uid,
                  photoUrl: providedPhotos[uid] ?? resolvedInfos[uid]?.photoUrl,
                  completion: ((counts[uid] ?? 0) / totalItems).clamp(0.0, 1.0),
                ),
            ]);
          }
        } catch (e, st) {
          await _safeLog(e, st);
          if (!controller.isClosed) controller.addError(e, st);
        }
      }

      final subMembers = membersSnaps.listen(
        (snap) {
          latestMembers = snap;
          unawaited(emit());
        },
        onError: (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        },
      );
      final subSched = scheduleSnaps.listen(
        (snap) {
          latestSchedule = snap;
          unawaited(emit());
        },
        onError: (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        },
      );
      final subEntries = entriesSnaps.listen(
        (snap) {
          latestEntries = snap;
          unawaited(emit());
        },
        onError: (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        },
      );

      controller.onCancel = () {
        subMembers.cancel();
        subSched.cancel();
        subEntries.cancel();
      };
    });
  }

  /// Fetch a limited list of members for a group, including their display names
  /// and photo URLs. Useful for displaying group cards.
  Future<List<GroupMemberProgressData>> getGroupMembersBasic(
    String groupId, {
    int limit = 4,
  }) async {
    try {
      final membersRef = firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.members);

      final snap = await membersRef.limit(limit).get();

      final order = <String>[];
      final providedNames = <String, String>{};
      final providedPhotos = <String, String>{};
      final missingUids = <String>[];

      for (final doc in snap.docs) {
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
        final photoUrl = data['photoUrl'] as String?;
        if (photoUrl != null && photoUrl.isNotEmpty) {
          providedPhotos[uid] = photoUrl;
        }
      }

      final resolvedInfos = await _fetchUserInfos(missingUids);

      return [
        for (final uid in order)
          GroupMemberProgressData(
            uid: uid,
            name: providedNames[uid] ?? resolvedInfos[uid]?.name ?? uid,
            photoUrl: providedPhotos[uid] ?? resolvedInfos[uid]?.photoUrl,
            completion: 0.0,
          ),
      ];
    } catch (e, st) {
      await _safeLog(e, st);
      return [];
    }
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
    final providedPhotos = <String, String>{};
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
      final photoUrl = data['photoUrl'] as String?;
      if (photoUrl != null && photoUrl.isNotEmpty) {
        providedPhotos[uid] = photoUrl;
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

    final resolvedInfos = await _fetchUserInfos(missingUids);

    // Determine total schedule items (chapters) for the date.
    final dateId = GroupService.dateId(date);
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
            name: providedNames[uid] ?? resolvedInfos[uid]?.name ?? uid,
            photoUrl: providedPhotos[uid] ?? resolvedInfos[uid]?.photoUrl,
            completion: 0.0,
          ),
      ];
    }

    // Compute completion as itemsChecked / totalItems.
    // We assume the 'count' field on the entry document is accurate.
    // This avoids N+1 queries to fetch the 'items' subcollection.
    final counts = <String, int>{};
    for (final doc in progressSnap.docs) {
      final uid = doc.id;
      final data = doc.data();
      final count = (data['count'] as num?)?.toInt();
      if (count != null) {
        counts[uid] = count;
      }
    }

    return [
      for (final uid in order)
        GroupMemberProgressData(
          uid: uid,
          name: providedNames[uid] ?? resolvedInfos[uid]?.name ?? uid,
          photoUrl: providedPhotos[uid] ?? resolvedInfos[uid]?.photoUrl,
          completion: ((counts[uid] ?? 0) / totalItems).clamp(0.0, 1.0),
        ),
    ];
  }

  Future<Map<String, _UserInfo>> _fetchUserInfos(List<String> uids) async {
    if (uids.isEmpty) {
      return <String, _UserInfo>{};
    }

    final uniqueUids = uids.toSet().toList();
    // ⚡ Bolt: Fetch missing users in parallel to reduce N+1 queries.
    // Use mapped gets to avoid limit constraints and reduce query payload size.
    final futures = <Future<List<DocumentSnapshot<Map<String, dynamic>>>>>[];
    for (var i = 0; i < uniqueUids.length; i += 30) {
      final end = i + 30 > uniqueUids.length ? uniqueUids.length : i + 30;
      final batch = uniqueUids.sublist(i, end);
      futures.add(
        Future.wait(
          batch.map((uid) => firestore.collection('users').doc(uid).get()),
        ),
      );
    }

    final infos = <String, _UserInfo>{};
    if (futures.isEmpty) {
      return infos;
    }

    final results = await Future.wait(futures);
    for (final chunkResults in results) {
      for (final user in chunkResults) {
        if (!user.exists) continue;
        final data = user.data()!;
        final chosen = _resolveDisplayName(data);
        final photoUrl = (data['photoURL'] as String?)?.trim();
        if (chosen != null) {
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
      await firestore.collection(GroupCollections.groups).doc(groupId).set({
        'name': name,
      }, SetOptions(merge: true));
    } catch (e, st) {
      await _safeLog(e, st);
      rethrow;
    }
  }

  /// Update the group's public status.
  Future<void> updateGroupPublicStatus({
    required String groupId,
    required bool isPublic,
  }) async {
    try {
      await firestore.collection(GroupCollections.groups).doc(groupId).set({
        'isPublic': isPublic,
      }, SetOptions(merge: true));
    } catch (e, st) {
      await _safeLog(e, st);
      rethrow;
    }
  }

  /// Remove a member from the group.
  Future<void> kickMember({
    required String groupId,
    required String uid,
  }) async {
    // Re-use leaveGroup logic as it handles cleanup.
    return leaveGroup(groupId: groupId, uid: uid);
  }

  /// Stream of group members with their roles and profile basics, ordered
  /// owner → admin → member then by name.
  Stream<List<GroupMemberRole>> membersWithRoles(String groupId) {
    return firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.members)
        .snapshots()
        .map((snap) {
      final members = snap.docs.map(GroupMemberRole.fromFirestore).toList();
      members.sort((a, b) {
        final byRole = a.roleRank.compareTo(b.roleRank);
        if (byRole != 0) return byRole;
        return (a.name ?? '').toLowerCase().compareTo(
              (b.name ?? '').toLowerCase(),
            );
      });
      return members;
    });
  }

  /// Stream of pending invitations for [groupId], most recent first.
  Stream<List<GroupInvite>> pendingInvites(String groupId) {
    return firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.invites)
        .snapshots()
        .map((snap) {
      final invites = snap.docs.map(GroupInvite.fromFirestore).toList();
      invites.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return invites;
    });
  }

  /// Cancel a pending invitation. Only owners/admins may do this (enforced by
  /// Firestore rules).
  Future<void> cancelInvite({
    required String groupId,
    required String inviteeUid,
  }) async {
    try {
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.invites)
          .doc(inviteeUid)
          .delete();
    } catch (e, st) {
      await _safeLog(e, st);
      rethrow;
    }
  }

  /// Transfer ownership of [groupId] from [currentOwnerUid] to [newOwnerUid].
  ///
  /// Atomically sets the group's `ownerUid`, promotes the new owner's member
  /// record to `owner`, and demotes the previous owner to `admin`.
  Future<void> transferOwnership({
    required String groupId,
    required String currentOwnerUid,
    required String newOwnerUid,
  }) async {
    if (currentOwnerUid == newOwnerUid) return;
    try {
      final groupRef =
          firestore.collection(GroupCollections.groups).doc(groupId);
      final groupSnap = await groupRef.get();
      final actualOwner = groupSnap.data()?['ownerUid'] as String?;
      if (actualOwner != currentOwnerUid) {
        throw StateError('Only the group owner can transfer ownership.');
      }

      final membersRef = groupRef.collection(GroupCollections.members);
      final newOwnerRef = membersRef.doc(newOwnerUid);
      final newOwnerSnap = await newOwnerRef.get();
      if (!newOwnerSnap.exists) {
        throw StateError('Cannot transfer ownership to a non-member.');
      }

      final batch = firestore.batch();
      batch.update(groupRef, {'ownerUid': newOwnerUid});
      batch.update(newOwnerRef, {'role': 'owner'});
      batch.update(membersRef.doc(currentOwnerUid), {'role': 'admin'});
      await batch.commit();
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

      // Track failures to decide if we can delete the root document
      final failures = <String>[];

      // 1. Members, Schedule, Join Requests
      final baseCollections = [
        GroupCollections.members,
        GroupCollections.schedule,
        GroupCollections.joinRequests,
      ];

      await Future.wait(
        baseCollections.map((coll) async {
          try {
            final snap = await groupRef.collection(coll).get();
            if (snap.docs.isNotEmpty) {
              await _deleteInBatches(
                  snap.docs.map((d) => d.reference).toList());
            }
          } catch (e, st) {
            failures.add(coll);
            await _safeLog(e, st);
          }
        }),
      );

      // 2. Progress entries (progress/{dateId}/entries/* and date docs)
      try {
        final refsToDelete = <DocumentReference>[];
        final progressDates = await groupRef.collection('progress').get();
        final allDateDocs = progressDates.docs;

        // Iterate per-date in chunks. This covers both modern entries (with groupId)
        // and legacy ones, so a separate collectionGroup query would be redundant.
        const chunkSize = 50;
        for (var i = 0; i < allDateDocs.length; i += chunkSize) {
          final chunk = allDateDocs.sublist(
            i,
            i + chunkSize > allDateDocs.length
                ? allDateDocs.length
                : i + chunkSize,
          );

          final entriesSnapshots = await Future.wait(
            chunk.map((d) async {
              try {
                return await d.reference.collection('entries').get();
              } catch (e, st) {
                await _safeLog(e, st);
                return null;
              }
            }),
          );

          for (final snap in entriesSnapshots) {
            if (snap != null) {
              for (final entryDoc in snap.docs) {
                refsToDelete.add(entryDoc.reference);
              }
            }
          }

          for (final dateDoc in chunk) {
            refsToDelete.add(dateDoc.reference);
          }
        }

        if (refsToDelete.isNotEmpty) {
          await _deleteInBatches(refsToDelete);
        }
      } catch (e, st) {
        failures.add('progress');
        await _safeLog(e, st);
      }

      // 3. progressSummary
      try {
        final summarySnap =
            await groupRef.collection('progressSummary').doc('data').get();
        if (summarySnap.exists) {
          await summarySnap.reference.delete();
        }
      } catch (e, st) {
        failures.add('progressSummary');
        await _safeLog(e, st);
      }

      // Finally delete the group document only if no critical sub-collections failed to clear.
      // We allow some flexibility but prefer a clean state.
      if (failures.isEmpty) {
        await groupRef.delete();
      } else {
        throw StateError(
          'Failed to clean up all sub-collections: ${failures.join(', ')}. Group document preserved.',
        );
      }
    } catch (e, st) {
      await _safeLog(e, st);
      rethrow;
    }
  }

  Future<void> _deleteInBatches(List<DocumentReference> refs) async {
    const batchSize = 500;
    for (var i = 0; i < refs.length; i += batchSize) {
      final batch = firestore.batch();
      final end = (i + batchSize < refs.length) ? i + batchSize : refs.length;
      for (var j = i; j < end; j++) {
        batch.delete(refs[j]);
      }
      await batch.commit();
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

      // ⚡ Bolt: Use a hybrid approach. First, try fetching all entries using a single
      // collectionGroup query. This relies on 'groupId' being present.
      final entriesSnap = await firestore
          .collectionGroup('entries')
          .where('uid', isEqualTo: uid)
          .where('groupId', isEqualTo: groupId)
          .get();

      final foundEntryRefs = entriesSnap.docs.map((d) => d.reference).toSet();
      final allDateSnaps = await groupRef.collection('progress').get();

      // For any date that wasn't found by the collectionGroup query, we must fetch
      // it individually to handle legacy data (missing groupId) and ensure correctness.
      final missingDates = allDateSnaps.docs.where((dateDoc) {
        final entryRef = dateDoc.reference.collection('entries').doc(uid);
        return !foundEntryRefs.contains(entryRef);
      }).toList();

      final fallbackSnaps = <DocumentSnapshot<Map<String, dynamic>>>[];
      if (missingDates.isNotEmpty) {
        // Fetch missing entries in parallel chunks.
        const chunkSize = 30;
        for (var i = 0; i < missingDates.length; i += chunkSize) {
          final chunk = missingDates.sublist(
            i,
            i + chunkSize > missingDates.length
                ? missingDates.length
                : i + chunkSize,
          );
          final futures = chunk.map(
            (d) => d.reference.collection('entries').doc(uid).get(),
          );
          fallbackSnaps.addAll(await Future.wait(futures));
        }
      }

      int total = 0;
      final repairFutures = <Future<int>>[];

      final allRelevantSnaps = [
        ...entriesSnap.docs,
        ...fallbackSnaps.where((s) => s.exists),
      ];

      for (final entrySnap in allRelevantSnaps) {
        final entryRef = entrySnap.reference;
        final data = entrySnap.data();

        final count = (data?['count'] as num?)?.toInt();

        // Backfill groupId if missing — but only when count is present, since the
        // count-repair branch below already writes groupId in the same set().
        if (data != null && !data.containsKey('groupId') && count != null) {
          unawaited(
            entryRef.set({
              'groupId': groupId,
              'uid': uid,
              'dateId': entryRef.parent.parent?.id,
            }, SetOptions(merge: true)),
          );
        }

        if (count != null) {
          total += count;
        } else {
          // If 'count' is missing, calculate it from 'items' subcollection.
          // We do this in parallel for all missing entries.
          repairFutures.add(() async {
            try {
              final itemsSnap = await entryRef.collection('items').get();
              final c = itemsSnap.docs.length;
              try {
                await entryRef.set({
                  'count': c,
                  'uid': uid,
                  'groupId': groupId,
                  'dateId': entryRef.parent.parent?.id,
                }, SetOptions(merge: true));
              } catch (_) {}
              return c;
            } catch (e, st) {
              await _safeLog(e, st);
              return 0;
            }
          }());
        }
      }

      if (repairFutures.isNotEmpty) {
        final repairedCounts = await Future.wait(repairFutures);
        total += repairedCounts.fold(0, (acc, c) => acc + c);
      }

      final summaryRef = groupRef
          .collection('progressSummary')
          .doc('data')
          .collection('entries')
          .doc(uid);
      await summaryRef.set({
        'completed': total,
        'uid': uid,
      }, SetOptions(merge: true));
    } catch (e, st) {
      await _safeLog(e, st);
    }
  }

  Future<List<Group>> _fetchGroupsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final uniqueIds = ids.toSet().toList();
    final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];

    for (var i = 0; i < uniqueIds.length; i += 30) {
      final end = i + 30 > uniqueIds.length ? uniqueIds.length : i + 30;
      final batch = uniqueIds.sublist(i, end);
      futures.add(
        firestore
            .collection(GroupCollections.groups)
            .where(FieldPath.documentId, whereIn: batch)
            .get(),
      );
    }

    final results = await Future.wait(futures);
    return results
        .expand((snap) => snap.docs)
        .map(Group.fromFirestore)
        .toList();
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

      final memberGroupIds = memberSnaps.docs
          .map((doc) => doc.reference.parent.parent?.id)
          .whereType<String>()
          .toList();

      final memberGroups = await _fetchGroupsByIds(memberGroupIds);
      for (final g in memberGroups) {
        groups[g.id] = g;
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

      await Future.wait(
        groups.values.map(
          (g) => recalcProgressForUserInGroup(groupId: g.id, uid: uid),
        ),
      );
    } catch (e, st) {
      await _safeLog(e, st);
    }
  }

  /// Toggles the read status for a specific user on a specific date in a group.
  ///
  /// If [schedule.chapters] is not empty, it updates the 'count' and 'items'
  /// sub-collection. If [schedule.chapters] is empty, it toggles the 'done' flag.
  Future<bool> toggleReadStatus({
    required String groupId,
    required String uid,
    required GroupSchedule schedule,
    required bool read,
    Set<int>? currentlyChecked,
  }) async {
    try {
      final dateKey = dateId(schedule.date);
      final db = firestore;
      final entryRef = db
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('progress')
          .doc(dateKey)
          .collection('entries')
          .doc(uid);
      final summaryRef = db
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('progressSummary')
          .doc('data')
          .collection('entries')
          .doc(uid);

      if (schedule.chapters.isEmpty) {
        if (read) {
          await entryRef.set({
            'done': true,
            'ts': FieldValue.serverTimestamp(),
            'uid': uid,
            'groupId': groupId,
            'dateId': dateKey,
          }, SetOptions(merge: true));
        } else {
          await entryRef.delete();
        }
        return true;
      }

      await db.runTransaction((tx) async {
        final snapshots =
            await Future.wait<DocumentSnapshot<Map<String, dynamic>>>([
          tx.get(entryRef),
          tx.get(summaryRef),
        ]);
        final entrySnap = snapshots[0];
        final summarySnap = snapshots[1];
        final nowTs = FieldValue.serverTimestamp();
        final currentCount = (entrySnap.data()?['count'] as num?)?.toInt() ??
            (currentlyChecked?.length ?? 0);
        final desiredCount = read ? schedule.chapters.length : 0;
        final delta = desiredCount - currentCount;
        final itemsCollection = entryRef.collection('items');
        final prevCompleted =
            (summarySnap.data()?['completed'] as num?)?.toInt() ?? 0;

        if (read) {
          for (var i = 0; i < schedule.chapters.length; i++) {
            if (currentlyChecked?.contains(i) ?? false) continue;
            tx.set(itemsCollection.doc(i.toString()), {
              'done': true,
              'ts': nowTs,
            });
          }
          tx.set(
              entryRef,
              {
                'done': true,
                'ts': nowTs,
                'uid': uid,
                'groupId': groupId,
                'dateId': dateKey,
                'count': desiredCount,
              },
              SetOptions(merge: true));
        } else {
          if (currentlyChecked != null && currentlyChecked.isNotEmpty) {
            for (final idx in currentlyChecked) {
              tx.delete(itemsCollection.doc(idx.toString()));
            }
          } else {
            // If we don't know what's checked, we have to fetch them or assume all
            // But we are in a transaction, so we can't easily fetch a collection.
            // However, we can probably just delete all possible indexes if small
            for (var i = 0; i < schedule.chapters.length; i++) {
              tx.delete(itemsCollection.doc(i.toString()));
            }
          }

          if (entrySnap.exists) {
            if (desiredCount == 0) {
              tx.delete(entryRef);
            } else {
              tx.update(entryRef, {'count': desiredCount, 'ts': nowTs});
            }
          }
        }

        if (delta != 0) {
          final updatedCompleted = prevCompleted + delta;
          tx.set(
              summaryRef,
              {
                'completed': updatedCompleted < 0 ? 0 : updatedCompleted,
                'uid': uid,
              },
              SetOptions(merge: true));
        }
      });
      return true;
    } catch (e, st) {
      await _safeLog(e, st);
      return false;
    }
  }

  /// Stream of completion counts/status for each day in the schedule for a specific user.
  ///
  /// Returns a map where key is dateId and value is the count of chapters read.
  Stream<Map<String, int>> userProgressForGroup(String groupId, String uid) {
    return firestore
        .collectionGroup('entries')
        .where('groupId', isEqualTo: groupId)
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final progress = <String, int>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final dateId = data['dateId'] as String?;
        final count = (data['count'] as num?)?.toInt() ?? 0;
        final done = data['done'] as bool? ?? false;
        if (dateId != null) {
          progress[dateId] = count > 0 ? count : (done ? 1 : 0);
        }
      }
      return progress;
    });
  }
}

class _UserInfo {
  final String name;
  final String? photoUrl;
  _UserInfo(this.name, this.photoUrl);
}
