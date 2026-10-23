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

  final Map<String, String> _profileNameCache = {};

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

  /// Ids of every active Group [uid] belongs to or owns.
  Future<Set<String>> fetchGroupIds(String uid) async {
    final results = await Future.wait([
      firestore
          .collectionGroup(GroupCollections.members)
          .where('uid', isEqualTo: uid)
          .get(),
      firestore
          .collection(GroupCollections.groups)
          .where('ownerUid', isEqualTo: uid)
          .where('deletedAt', isNull: true)
          .get(),
    ]);
    return <String>{
      ...results[0]
          .docs
          .map((doc) => doc.reference.parent.parent?.id)
          .whereType<String>(),
      ...results[1].docs.map((doc) => doc.id),
    };
  }

  /// Everyone [uid] shares at least one Group with, plus their Friends.
  /// Derived at read time; never stored. Pending join requests confer
  /// nothing. The reader themselves is excluded.
  Future<Set<String>> fetchCircleMemberIds(String uid) async {
    final groupIds = await fetchGroupIds(uid);

    final circle = <String>{};
    for (final groupId in groupIds) {
      final results = await Future.wait([
        firestore
            .collection(GroupCollections.groups)
            .doc(groupId)
            .collection(GroupCollections.members)
            .get(),
        firestore.collection(GroupCollections.groups).doc(groupId).get(),
      ]);
      final members = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final groupDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>;
      for (final member in members.docs) {
        final id = (member.data()['uid'] as String?) ?? member.id;
        if (id != uid && id.isNotEmpty) circle.add(id);
      }
      final ownerUid = (groupDoc.data()?['ownerUid'] as String?)?.trim();
      if (ownerUid != null && ownerUid.isNotEmpty && ownerUid != uid) {
        circle.add(ownerUid);
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

  /// Live stream of Group IDs [uid] belongs to or owns.
  Stream<Set<String>> watchGroupIds(String uid) {
    final memberships = firestore
        .collectionGroup(GroupCollections.members)
        .where('uid', isEqualTo: uid)
        .snapshots();
    final owned = firestore
        .collection(GroupCollections.groups)
        .where('ownerUid', isEqualTo: uid)
        .where('deletedAt', isNull: true)
        .snapshots();

    return Stream<Set<String>>.multi((controller) {
      Set<String>? memberGroupIds;
      Set<String>? ownedGroupIds;
      var closed = false;

      void emit() {
        if (closed || controller.isClosed) return;
        if (memberGroupIds == null || ownedGroupIds == null) return;
        controller.add({...memberGroupIds!, ...ownedGroupIds!});
      }

      final subs = <StreamSubscription<dynamic>>[];
      subs.add(memberships.listen(
        (snap) {
          memberGroupIds = snap.docs
              .map((doc) => doc.reference.parent.parent?.id)
              .whereType<String>()
              .toSet();
          emit();
        },
        onError: (Object e, StackTrace st) {
          unawaited(_safeLog(e, st));
          memberGroupIds = const <String>{};
          emit();
        },
      ));
      subs.add(owned.listen(
        (snap) {
          ownedGroupIds = snap.docs.map((doc) => doc.id).toSet();
          emit();
        },
        onError: (Object e, StackTrace st) {
          unawaited(_safeLog(e, st));
          ownedGroupIds = const <String>{};
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

  Stream<List<CircleMember>> _watchCoMembers(String uid) {
    final groupIdsStream = watchGroupIds(uid);

    return Stream<List<CircleMember>>.multi((controller) {
      final groupSubs =
          <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
      final groupDocSubs = <String,
          StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
      final perGroup = <String, List<CircleMember>>{};
      final perGroupOwner = <String, String?>{};
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
          if (perGroup.containsKey(groupId) == false ||
              perGroupOwner.containsKey(groupId) == false) {
            return;
          }
        }

        final byUid = <String, CircleMember>{};
        for (final groupId in activeGroupIds) {
          final members = List<CircleMember>.from(
            perGroup[groupId] ?? const <CircleMember>[],
          );
          final ownerUid = perGroupOwner[groupId];
          if (ownerUid != null &&
              ownerUid.isNotEmpty &&
              ownerUid != uid &&
              members.every((m) => m.uid != ownerUid)) {
            members.add(CircleMember(uid: ownerUid, groupIds: {groupId}));
          }
          for (final member in members) {
            final existing = byUid[member.uid];
            if (existing == null) {
              byUid[member.uid] = CircleMember(
                uid: member.uid,
                groupIds: {groupId},
                name: member.name,
                photoUrl: member.photoUrl,
              );
            } else {
              byUid[member.uid] = CircleMember(
                uid: existing.uid,
                groupIds: {...existing.groupIds, groupId},
                name: existing.name ?? member.name,
                photoUrl: existing.photoUrl ?? member.photoUrl,
              );
            }
          }
        }
        controller.add(byUid.values.toList());
      }

      void cancelGroup(String groupId) {
        groupSubs.remove(groupId)?.cancel();
        groupDocSubs.remove(groupId)?.cancel();
        perGroup.remove(groupId);
        perGroupOwner.remove(groupId);
      }

      final membershipSub = groupIdsStream.listen(
        (groupIds) {
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
            groupDocSubs[groupId] = firestore
                .collection(GroupCollections.groups)
                .doc(groupId)
                .snapshots()
                .listen(
              (groupSnap) {
                perGroupOwner[groupId] =
                    (groupSnap.data()?['ownerUid'] as String?)?.trim();
                emit();
              },
              onError: (Object e, StackTrace st) {
                unawaited(_safeLog(e, st));
                perGroupOwner[groupId] = null;
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
        for (final subscription in groupDocSubs.values) {
          subscription.cancel();
        }
      };
    });
  }

  Future<String> _resolveDisplayName(
    String uid, {
    String? circleName,
    String? entryName,
  }) async {
    final fromCircle = circleName?.trim();
    if (fromCircle != null && fromCircle.isNotEmpty) return fromCircle;
    final fromEntry = entryName?.trim();
    if (fromEntry != null && fromEntry.isNotEmpty) return fromEntry;
    final cached = _profileNameCache[uid];
    if (cached != null) return cached;
    try {
      final profile = await firestore.collection('users').doc(uid).get();
      final data = profile.data();
      final name = ((data?['name'] as String?) ??
              (data?['displayName'] as String?) ??
              (data?['username'] as String?))
          ?.trim();
      if (name != null && name.isNotEmpty) {
        _profileNameCache[uid] = name;
        return name;
      }
    } catch (_) {}
    return '?';
  }

  /// One-shot fetch of today's Circle presence for [uid] on [dateKey] (`YYYY-MM-DD`).
  Future<CirclePresenceSnapshot> fetchDailyPresence(
    String uid, {
    required String dateKey,
  }) async {
    final circleMembers = await watchCircleMembers(uid).first.timeout(
          const Duration(seconds: 5),
          onTimeout: () => const <CircleMember>[],
        );
    final circleByUid = <String, CircleMember>{
      for (final m in circleMembers) m.uid: m,
    };
    final allUids = <String>{uid, ...circleByUid.keys};
    final groupIds = await fetchGroupIds(uid).timeout(
      const Duration(seconds: 5),
      onTimeout: () => const <String>{},
    );
    final friendTargetUids = <String>{
      uid,
      for (final m in circleMembers)
        if (m.isFriend) m.uid,
    };

    final entryNames = <String, String?>{};
    final groupSnaps = await Future.wait([
      for (final groupId in groupIds)
        firestore
            .collection(GroupCollections.groups)
            .doc(groupId)
            .collection('read_log')
            .doc(dateKey)
            .collection('entries')
            .get(),
    ]).timeout(
      const Duration(seconds: 5),
      onTimeout: () => const <QuerySnapshot<Map<String, dynamic>>>[],
    );
    for (final snap in groupSnaps) {
      for (final doc in snap.docs) {
        final authorUid = (doc.data()['uid'] as String?) ?? doc.id;
        if (allUids.contains(authorUid)) {
          entryNames[authorUid] ??= doc.data()['name'] as String?;
        }
      }
    }

    final friendSnaps = await Future.wait([
      for (final targetUid in friendTargetUids)
        FriendService.feedEntry(firestore, targetUid, dateKey).get(),
    ]).timeout(
      const Duration(seconds: 5),
      onTimeout: () => const <DocumentSnapshot<Map<String, dynamic>>>[],
    );
    for (final doc in friendSnaps) {
      if (!doc.exists) continue;
      final data = doc.data();
      final authorUid = (data?['uid'] as String?) ?? doc.id;
      if (allUids.contains(authorUid)) {
        entryNames[authorUid] ??= data?['name'] as String?;
      }
    }

    final readers = <CirclePresencePerson>[];
    for (final readerUid in entryNames.keys) {
      final circleMember = circleByUid[readerUid];
      final name = await _resolveDisplayName(
        readerUid,
        circleName: circleMember?.name,
        entryName: entryNames[readerUid],
      );
      readers.add(
        CirclePresencePerson(
          uid: readerUid,
          name: name,
          photoUrl: circleMember?.photoUrl,
        ),
      );
    }
    readers.sort((a, b) {
      if (a.uid == uid) return 1;
      if (b.uid == uid) return -1;
      return a.name.compareTo(b.name);
    });

    return CirclePresenceSnapshot(
      readers: readers,
      totalCount: allUids.length,
    );
  }

  /// Reactive stream of today's Circle presence for [uid] on [dateKey] (`YYYY-MM-DD`).
  Stream<CirclePresenceSnapshot> watchDailyPresence(
    String uid, {
    required String dateKey,
  }) {
    final groupIdsStream = watchGroupIds(uid);
    final circleStream = watchCircleMembers(uid);

    return Stream<CirclePresenceSnapshot>.multi((controller) {
      Set<String>? activeGroupIds;
      Map<String, CircleMember>? circleByUid;
      final groupEntrySubs =
          <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
      final friendEntrySubs = <String,
          StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
      final groupEntries = <String, Map<String, String?>>{};
      final friendEntries = <String, String?>{};
      final friendReported = <String>{};
      var closed = false;
      var emitGeneration = 0;

      Future<void> emit() async {
        if (closed || controller.isClosed) return;
        if (activeGroupIds == null || circleByUid == null) return;
        for (final g in activeGroupIds!) {
          if (!groupEntries.containsKey(g)) return;
        }
        final wantedFriends = <String>{
          uid,
          for (final m in circleByUid!.values)
            if (m.isFriend) m.uid,
        };
        for (final f in wantedFriends) {
          if (!friendReported.contains(f)) return;
        }

        final myGen = ++emitGeneration;
        final currentCircle = Map<String, CircleMember>.from(circleByUid!);
        final allUids = <String>{uid, ...currentCircle.keys};

        final entryNames = <String, String?>{};
        for (final g in activeGroupIds!) {
          final entries = groupEntries[g];
          if (entries == null) continue;
          for (final e in entries.entries) {
            if (allUids.contains(e.key)) {
              entryNames[e.key] ??= e.value;
            }
          }
        }
        for (final f in wantedFriends) {
          if (friendEntries.containsKey(f) && allUids.contains(f)) {
            entryNames[f] ??= friendEntries[f];
          }
        }

        final readers = <CirclePresencePerson>[];
        for (final readerUid in entryNames.keys) {
          final circleMember = currentCircle[readerUid];
          final name = await _resolveDisplayName(
            readerUid,
            circleName: circleMember?.name,
            entryName: entryNames[readerUid],
          );
          readers.add(
            CirclePresencePerson(
              uid: readerUid,
              name: name,
              photoUrl: circleMember?.photoUrl,
            ),
          );
        }
        if (closed || controller.isClosed || myGen != emitGeneration) return;

        readers.sort((a, b) {
          if (a.uid == uid) return 1;
          if (b.uid == uid) return -1;
          return a.name.compareTo(b.name);
        });

        controller.add(
          CirclePresenceSnapshot(
            readers: readers,
            totalCount: allUids.length,
          ),
        );
      }

      void syncGroupSubs() {
        final wanted = activeGroupIds ?? const <String>{};
        for (final existing in groupEntrySubs.keys.toList()) {
          if (!wanted.contains(existing)) {
            groupEntrySubs.remove(existing)?.cancel();
            groupEntries.remove(existing);
          }
        }
        for (final groupId in wanted) {
          if (groupEntrySubs.containsKey(groupId)) continue;
          groupEntrySubs[groupId] = firestore
              .collection(GroupCollections.groups)
              .doc(groupId)
              .collection('read_log')
              .doc(dateKey)
              .collection('entries')
              .snapshots()
              .listen(
            (snap) {
              groupEntries[groupId] = {
                for (final doc in snap.docs)
                  ((doc.data()['uid'] as String?) ?? doc.id):
                      doc.data()['name'] as String?,
              };
              unawaited(emit());
            },
            onError: (Object e, StackTrace st) {
              unawaited(_safeLog(e, st));
              groupEntries[groupId] = const <String, String?>{};
              unawaited(emit());
            },
          );
        }
      }

      void syncFriendSubs() {
        final currentCircle = circleByUid;
        if (currentCircle == null) return;
        final wanted = <String>{
          uid,
          for (final m in currentCircle.values)
            if (m.isFriend) m.uid,
        };
        for (final existing in friendEntrySubs.keys.toList()) {
          if (!wanted.contains(existing)) {
            friendEntrySubs.remove(existing)?.cancel();
            friendEntries.remove(existing);
            friendReported.remove(existing);
          }
        }
        for (final targetUid in wanted) {
          if (friendEntrySubs.containsKey(targetUid)) continue;
          friendEntrySubs[targetUid] =
              FriendService.feedEntry(firestore, targetUid, dateKey)
                  .snapshots()
                  .listen(
            (doc) {
              if (doc.exists) {
                friendEntries[targetUid] = doc.data()?['name'] as String?;
              } else {
                friendEntries.remove(targetUid);
              }
              friendReported.add(targetUid);
              unawaited(emit());
            },
            onError: (Object e, StackTrace st) {
              unawaited(_safeLog(e, st));
              friendEntries.remove(targetUid);
              friendReported.add(targetUid);
              unawaited(emit());
            },
          );
        }
      }

      final subs = <StreamSubscription<dynamic>>[];
      subs.add(groupIdsStream.listen(
        (groupIds) {
          activeGroupIds = groupIds;
          syncGroupSubs();
          unawaited(emit());
        },
        onError: (Object e, StackTrace st) {
          unawaited(_safeLog(e, st));
          activeGroupIds = const <String>{};
          syncGroupSubs();
          unawaited(emit());
        },
      ));
      subs.add(circleStream.listen(
        (members) {
          circleByUid = {for (final m in members) m.uid: m};
          syncFriendSubs();
          unawaited(emit());
        },
        onError: (Object e, StackTrace st) {
          unawaited(_safeLog(e, st));
          circleByUid = const <String, CircleMember>{};
          syncFriendSubs();
          unawaited(emit());
        },
      ));

      controller.onCancel = () {
        closed = true;
        for (final sub in subs) {
          unawaited(sub.cancel());
        }
        for (final sub in groupEntrySubs.values) {
          unawaited(sub.cancel());
        }
        for (final sub in friendEntrySubs.values) {
          unawaited(sub.cancel());
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
