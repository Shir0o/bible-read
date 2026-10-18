import 'dart:async';

import 'package:bible_read/models/circle_member.dart';
import 'package:bible_read/services/feed_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// ADR-0012: the Feed merges the reader's Groups with their Friends' own
// per-author sources. A person both Friends with and in a Group with the
// reader appears once, and an Amen is written on every copy the update came
// from.

Future<T> nextWhere<T>(Stream<T> stream, bool Function(T value) predicate) {
  final completer = Completer<T>();
  late StreamSubscription<T> subscription;
  subscription = stream.listen((value) {
    if (predicate(value) && !completer.isCompleted) {
      completer.complete(value);
      subscription.cancel();
    }
  });
  return completer.future;
}

void main() {
  late FakeFirebaseFirestore firestore;
  final today = DateTime(2026, 10, 18);

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  Future<void> seedGroup(String id, {String ownerUid = 'me'}) async {
    await firestore.collection('groups').doc(id).set({
      'name': 'Group $id',
      'ownerUid': ownerUid,
    });
    await firestore
        .collection('groups')
        .doc(id)
        .collection('members')
        .doc(ownerUid)
        .set({'uid': ownerUid});
    await firestore
        .collection('groups')
        .doc(id)
        .collection('members')
        .doc('me')
        .set({'uid': 'me'});
  }

  Future<void> seedGroupEntry(
    String groupId,
    String uid, {
    String? reflection,
  }) async {
    await firestore
        .collection('groups')
        .doc(groupId)
        .collection('read_log')
        .doc('2026-10-18')
        .collection('entries')
        .doc(uid)
        .set({
      'uid': uid,
      'name': 'Mei',
      'timestamp': DateTime(2026, 10, 18, 7, 40),
      if (reflection != null) 'sharedReflection': reflection,
    });
  }

  Future<void> seedFriendEntry(
    String authorUid, {
    String? reflection,
  }) async {
    await firestore
        .collection('users')
        .doc(authorUid)
        .collection('friend_feed')
        .doc('2026-10-18')
        .collection('entries')
        .doc(authorUid)
        .set({
      'uid': authorUid,
      'name': 'Mei',
      'timestamp': DateTime(2026, 10, 18, 7, 40),
      if (reflection != null) 'sharedReflection': reflection,
    });
  }

  group('FeedService.watch', () {
    test('merges a Friend source with the Group sources', () async {
      await seedGroup('g1');
      await seedGroupEntry('g1', 'me');
      await seedFriendEntry('friend');

      final source = await FeedService(firestore: firestore).watch(['g1'],
          friendUids: ['friend'],
          today:
              today).firstWhere((s) => s.entries.any((e) => e.uid == 'friend'));

      expect(source.entries.map((e) => e.uid), containsAll(['me', 'friend']));
      final friendCopy = source.entries.firstWhere((e) => e.uid == 'friend');
      expect(friendCopy.isFriend, isTrue);
      expect(friendCopy.friendUid, 'friend');
    });

    test('reads a Friend source with no Groups', () async {
      await seedFriendEntry('friend');

      final source = await FeedService(firestore: firestore).watch(const [],
          friendUids: ['friend'],
          today: today).firstWhere((s) => s.entries.isNotEmpty);

      expect(source.entries.single.uid, 'friend');
    });

    test('merges Friend badge logs', () async {
      await firestore
          .collection('users')
          .doc('friend')
          .collection('friend_badge_log')
          .doc('friend_days_7')
          .set({
        'uid': 'friend',
        'badgeId': 'days_7',
        'type': 'consistency',
        'dateUnlocked': DateTime(2026, 10, 18),
      });

      final source = await FeedService(firestore: firestore).watch(const [],
          friendUids: ['friend'],
          today: today).firstWhere((s) => s.badges.isNotEmpty);

      expect(source.badges.single.mirror.uid, 'friend');
      expect(source.badges.single.friendUid, 'friend');
    });
  });

  group('assembleFeed with Friends', () {
    test('a Friend day is labelled Friend and carries its own Amen target',
        () async {
      await seedFriendEntry('friend');
      final source = await FeedService(firestore: firestore).watch(const [],
          friendUids: ['friend'],
          today: today).firstWhere((s) => s.entries.isNotEmpty);

      final days = assembleFeed(
        source: source,
        myUid: 'me',
        myName: 'Me',
        myPhotoUrl: null,
        circle: const [
          CircleMember(uid: 'friend', groupIds: {}, isFriend: true),
        ],
        groupIds: const {},
        friendUids: const {'friend'},
        today: today,
      );

      final update = days.single.updates.single;
      expect(update.isFriend, isTrue);
      expect(update.groupIds, isEmpty);
      expect(update.targets.single.friendUid, 'friend');
      expect(
        update.targets.single.likesPath,
        'users/friend/friend_feed/2026-10-18/entries/friend/likes',
      );
    });

    test(
        'a Friend who also shares a Group collapses to one update and one Amen',
        () async {
      await seedGroup('g1');
      await seedGroupEntry('g1', 'friend');
      await seedFriendEntry('friend');
      final source = await FeedService(firestore: firestore)
          .watch(['g1'], friendUids: ['friend'], today: today).firstWhere(
              (s) => s.entries.where((e) => e.uid == 'friend').length == 2);

      final days = assembleFeed(
        source: source,
        myUid: 'me',
        myName: 'Me',
        myPhotoUrl: null,
        circle: const [
          CircleMember(uid: 'friend', groupIds: {'g1'}, isFriend: true),
        ],
        groupIds: const {'g1'},
        friendUids: const {'friend'},
        today: today,
      );

      final update = days.single.updates.single;
      expect(update.groupIds, {'g1'});
      expect(update.isFriend, isTrue);
      expect(update.targets, hasLength(2));
      expect(
        update.targets.map((t) => t.likesPath),
        containsAll([
          'groups/g1/read_log/2026-10-18/entries/friend/likes',
          'users/friend/friend_feed/2026-10-18/entries/friend/likes',
        ]),
      );
    });

    test('keeps a shared Reflection and drops an unshared one', () async {
      await seedFriendEntry('friend', reflection: 'Abram just goes.');
      final source = await FeedService(firestore: firestore).watch(const [],
          friendUids: ['friend'],
          today: today).firstWhere((s) => s.entries.isNotEmpty);

      final days = assembleFeed(
        source: source,
        myUid: 'me',
        myName: 'Me',
        myPhotoUrl: null,
        circle: const [
          CircleMember(uid: 'friend', groupIds: {}, isFriend: true),
        ],
        groupIds: const {},
        friendUids: const {'friend'},
        today: today,
      );
      expect(days.single.updates.single.reflection, 'Abram just goes.');
    });

    test('drops a Friend’s updates once unfriended', () async {
      await seedFriendEntry('friend');
      final source = await FeedService(firestore: firestore).watch(const [],
          friendUids: ['friend'],
          today: today).firstWhere((s) => s.entries.isNotEmpty);

      final days = assembleFeed(
        source: source,
        myUid: 'me',
        myName: 'Me',
        myPhotoUrl: null,
        circle: const [],
        groupIds: const {},
        friendUids: const {},
        today: today,
      );

      expect(days, isEmpty);
    });

    test('Amen writes to every copy the update came from', () async {
      await seedGroup('g1');
      await seedGroupEntry('g1', 'friend');
      await seedFriendEntry('friend');
      final source = await FeedService(firestore: firestore)
          .watch(['g1'], friendUids: ['friend'], today: today).firstWhere(
              (s) => s.entries.where((e) => e.uid == 'friend').length == 2);
      final update = assembleFeed(
        source: source,
        myUid: 'me',
        myName: 'Me',
        myPhotoUrl: null,
        circle: const [
          CircleMember(uid: 'friend', groupIds: {'g1'}, isFriend: true),
        ],
        groupIds: const {'g1'},
        friendUids: const {'friend'},
        today: today,
      ).single.updates.single;

      await FeedService(firestore: firestore).setAmen(
        targets: update.targets,
        uid: 'me',
        name: 'Me',
        amen: true,
      );

      final groupLike = await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc('2026-10-18')
          .collection('entries')
          .doc('friend')
          .collection('likes')
          .doc('me')
          .get();
      final friendLike = await firestore
          .collection('users')
          .doc('friend')
          .collection('friend_feed')
          .doc('2026-10-18')
          .collection('entries')
          .doc('friend')
          .collection('likes')
          .doc('me')
          .get();
      expect(groupLike.exists, isTrue);
      expect(friendLike.exists, isTrue);
    });
  });
}
