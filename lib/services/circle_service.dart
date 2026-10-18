import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/circle_member.dart';
import 'error_logger.dart';
import 'friend_service.dart';
import 'group_collections.dart';

/// Deep module encapsulating Circle derivation (ADR-0012).
///
/// A reader's Circle consists of everyone they share at least one Group with
/// plus their Friends. The Circle is derived dynamically from Group
/// membership and the friend graph; there is no stored circle collection.
///
/// This service encapsulates:
/// - One-shot lookup of Circle IDs across shared groups and Friends ([fetchCircleMemberIds]).
/// - Reactive streaming of deduplicated [CircleMember]s ([watchCircleMembers]).
/// - Observing co-members' reading progress / completed date keys in a group schedule ([memberCompletedDates]).
class CircleService {
  /// Firestore instance used for database operations.
  final FirebaseFirestore firestore;

  /// Source of the reader's Friends. Defaults to a [FriendService] on the
  /// same Firestore.
  final FriendService friendService;

  /// Creates a [CircleService] using [FirebaseFirestore.instance] by default.
  CircleService({
    FirebaseFirestore? firestore,
    FriendService? friendService,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        friendService = friendService ??
            FriendService(firestore: firestore ?? FirebaseFirestore.instance);

  static Future<void> _safeLog(Object e, StackTrace? st) async {
    try {
      await ErrorLogger.log(e, st);
    } catch (_) {}
  }

  /// Everyone [uid] shares at least one Group with, plus their Friends.
  /// Derived at read time; never stored. Pending join requests confer
  /// nothing. The reader themselves is excluded.
  Future<Set<String>> fetchCircleMemberIds(String uid) async {
    final memberships = await firestore
        .collectionGroup(GroupCollections.members)
        .where('uid', isEqualTo: uid)
        .get();
    final groupIds = memberships.docs
        .map((doc) => doc.reference.parent.parent?.id)
        .whereType<String>()
        .toSet();

    final circle = <String>{};
    for (final groupId in groupIds) {
      final members = await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.members)
          .get();
      for (final member in members.docs) {
        final id = (member.data()['uid'] as String?) ?? member.id;
        if (id != uid && id.isNotEmpty) circle.add(id);
      }
    }
    circle.addAll(await friendService.fetchFriendIds(uid));
    return circle;
  }

  /// Backward-compatible alias for [fetchCircleMemberIds].
  Future<Set<String>> circleMemberIds(String uid) => fetchCircleMemberIds(uid);

  /// Live stream of the reader's Circle (ADR-0012): the co-members of every
  /// Group [uid] belongs to, plus their Friends, deduplicated by uid. A person
  /// in two shared Groups appears once, carrying both Group ids; a Friend who
  /// also shares a Group keeps their Group ids and is marked [isFriend].
  /// The reader is excluded. No Groups and no Friends yields an empty list,
  /// not an error.
  Stream<List<CircleMember>> watchCircleMembers(String uid) {
    final coMembers = _watchCoMembers(uid);
    final friendMembers = friendService.watchFriends(uid).map(
          (friends) => [
            for (final friend in friends)
              CircleMember(
                uid: friend.uid,
                groupIds: const <String>{},
                name: friend.name,
                photoUrl: friend.photoUrl,
                isFriend: true,
                friendSince: friend.since,
              ),
          ],
        );

    return Stream<List<CircleMember>>.multi((controller) {
      List<CircleMember>? co;
      List<CircleMember>? friends;
      var closed = false;

      void emit() {
        if (closed || co == null || friends == null) return;
        final byUid = <String, CircleMember>{
          for (final member in co!) member.uid: member,
        };
        for (final friend in friends!) {
          final existing = byUid[friend.uid];
          byUid[friend.uid] = existing == null
              ? friend
              : CircleMember(
                  uid: existing.uid,
                  groupIds: existing.groupIds,
                  name: existing.name ?? friend.name,
                  photoUrl: existing.photoUrl ?? friend.photoUrl,
                  isFriend: true,
                  friendSince: friend.friendSince,
                );
        }
        controller.add(byUid.values.toList());
      }

      final subs = <StreamSubscription<dynamic>>[];

      subs.add(coMembers.listen(
        (members) {
          co = members;
          emit();
        },
        onError: (Object e, StackTrace st) {
          unawaited(_safeLog(e, st));
          co = const <CircleMember>[];
          emit();
        },
      ));

      subs.add(friendMembers.listen(
        (members) {
          friends = members;
          emit();
        },
        onError: (Object e, StackTrace st) {
          unawaited(_safeLog(e, st));
          friends = const <CircleMember>[];
          emit();
        },
      ));

      controller.onCancel = () {
        closed = true;
        for (final sub in subs) {
          unawaited(sub.cancel());
        }
      };
    });
  }

  /// Backward-compatible alias for [watchCircleMembers].
  Stream<List<CircleMember>> circleMembers(String uid) =>
      watchCircleMembers(uid);

  Stream<List<CircleMember>> _watchCoMembers(String uid) {
    final memberships = firestore
        .collectionGroup(GroupCollections.members)
        .where('uid', isEqualTo: uid)
        .snapshots();

    return Stream<List<CircleMember>>.multi((controller) {
      final groupSubs =
          <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
      final perGroup = <String, List<CircleMember>>{};
      var activeGroupIds = <String>{};
      var membershipsReported = false;
      var closed = false;

      CircleMember? memberFrom(
        QueryDocumentSnapshot<Map<String, dynamic>> doc,
        String groupId,
      ) {
        final data = doc.data();
        final id = (data['uid'] as String?) ?? doc.id;
        if (id.isEmpty || id == uid) return null;
        final name = (data['name'] as String?)?.trim();
        final photoUrl = (data['photoUrl'] as String?)?.trim();
        return CircleMember(
          uid: id,
          groupIds: {groupId},
          name: (name != null && name.isNotEmpty) ? name : null,
          photoUrl: (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : null,
        );
      }

      void emit() {
        if (controller.isClosed || closed) return;
        if (membershipsReported == false) return;
        for (final groupId in activeGroupIds) {
          if (perGroup.containsKey(groupId) == false) return;
        }

        final byUid = <String, CircleMember>{};
        for (final groupId in activeGroupIds) {
          for (final member in perGroup[groupId] ?? const <CircleMember>[]) {
            final existing = byUid[member.uid];
            if (existing == null) {
              byUid[member.uid] = CircleMember(
                uid: member.uid,
                groupIds: {groupId},
                name: member.name,
                photoUrl: member.photoUrl,
              );
            } else {
              existing.groupIds.add(groupId);
            }
          }
        }
        controller.add(byUid.values.toList());
      }

      void cancelGroup(String groupId) {
        groupSubs.remove(groupId)?.cancel();
        perGroup.remove(groupId);
      }

      final membershipSub = memberships.listen(
        (memberSnaps) {
          final groupIds = memberSnaps.docs
              .map((doc) => doc.reference.parent.parent?.id)
              .whereType<String>()
              .toSet();
          activeGroupIds = groupIds;

          for (final existing in groupSubs.keys.toList()) {
            if (groupIds.contains(existing) == false) {
              cancelGroup(existing);
            }
          }

          for (final groupId in groupIds) {
            if (groupSubs.containsKey(groupId)) continue;
            groupSubs[groupId] = firestore
                .collection(GroupCollections.groups)
                .doc(groupId)
                .collection(GroupCollections.members)
                .snapshots()
                .listen(
              (memberSnap) {
                final members = <CircleMember>[];
                for (final doc in memberSnap.docs) {
                  final member = memberFrom(doc, groupId);
                  if (member != null) members.add(member);
                }
                perGroup[groupId] = members;
                emit();
              },
              onError: (Object e, StackTrace st) {
                unawaited(_safeLog(e, st));
                perGroup[groupId] = const <CircleMember>[];
                emit();
              },
            );
          }

          membershipsReported = true;
          emit();
        },
        onError: (Object e, StackTrace st) {
          unawaited(_safeLog(e, st));
          membershipsReported = true;
          controller.addError(e, st);
        },
      );

      controller.onCancel = () {
        closed = true;
        membershipSub.cancel();
        for (final subscription in groupSubs.values) {
          subscription.cancel();
        }
      };
    });
  }

  /// Stream of the `YYYY-MM-DD` ids [uid] has completed in [groupId]'s
  /// schedule, read from `progress/{dateId}/entries/{uid}` (count > 0 or
  /// done). This is how a Circle row learns a co-member's Plan reading.
  Stream<Set<String>> memberCompletedDates(String groupId, String uid) {
    return firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection('progress')
        .snapshots()
        .asyncMap((snap) async {
      final done = <String>{};
      for (final day in snap.docs) {
        try {
          final entry =
              await day.reference.collection('entries').doc(uid).get();
          final data = entry.data();
          if (data == null) continue;
          final count = (data['count'] as num?)?.toInt() ?? 0;
          final complete = data['done'] == true;
          if (count > 0 || complete) done.add(day.id);
        } catch (e, st) {
          await _safeLog(e, st);
        }
      }
      return done;
    });
  }
}
