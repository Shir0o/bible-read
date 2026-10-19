import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/circle_member.dart';
import 'package:bible_read/services/circle_service.dart';

// ADR-0003: Circle is derived from Group membership; there is no friend graph.
// CircleService encapsulates this derivation:
// - Co-members across shared groups
// - Deduplication by uid, aggregation of groupIds
// - Exclusion of the reader themselves
// - Reactive streaming of CircleMembers and progress completed date keys.

Future<T> nextWhere<T>(Stream<T> stream, bool Function(T value) predicate) {
  final completer = Completer<T>();
  late StreamSubscription<T> subscription;
  subscription = stream.listen((value) {
    if (predicate(value) && completer.isCompleted == false) {
      completer.complete(value);
      subscription.cancel();
    }
  });
  return completer.future;
}

void main() {
  late FakeFirebaseFirestore firestore;
  late CircleService circleService;

  Future<String> seedGroup({
    required String id,
    required String ownerUid,
    List<Map<String, dynamic>> members = const [],
  }) async {
    await firestore.collection('groups').doc(id).set({
      'name': 'Group $id',
      'ownerUid': ownerUid,
      'memberCount': members.length + 1,
    });
    await firestore
        .collection('groups')
        .doc(id)
        .collection('members')
        .doc(ownerUid)
        .set({'uid': ownerUid, 'role': 'owner'});
    for (final member in members) {
      final uid = member['uid'] as String;
      await firestore
          .collection('groups')
          .doc(id)
          .collection('members')
          .doc(uid)
          .set(member);
    }
    return id;
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    circleService = CircleService(firestore: firestore);
  });

  group('CircleService.fetchCircleMemberIds', () {
    test('derives co-members from the groups the reader belongs to', () async {
      await seedGroup(
        id: 'g1',
        ownerUid: 'u1',
        members: [
          {'uid': 'u2', 'role': 'member'},
          {'uid': 'u3', 'role': 'member'},
        ],
      );

      final circle = await circleService.fetchCircleMemberIds('u2');
      expect(circle, {'u1', 'u3'});

      // Alias check
      final circleAlias = await circleService.circleMemberIds('u2');
      expect(circleAlias, {'u1', 'u3'});
    });

    test('a person shared by two Groups appears once', () async {
      await seedGroup(
        id: 'g1',
        ownerUid: 'u1',
        members: [
          {'uid': 'u2', 'role': 'member'},
        ],
      );
      await seedGroup(
        id: 'g2',
        ownerUid: 'u3',
        members: [
          {'uid': 'u2', 'role': 'member'},
        ],
      );

      final circle = await circleService.fetchCircleMemberIds('u2');
      expect(circle, {'u1', 'u3'});
    });

    test('the reader is not part of their own Circle', () async {
      await seedGroup(
        id: 'g1',
        ownerUid: 'u1',
        members: [
          {'uid': 'u2', 'role': 'member'},
          {'uid': 'u3', 'role': 'member'},
        ],
      );

      final circle = await circleService.fetchCircleMemberIds('u1');
      expect(circle, {'u2', 'u3'});
    });

    test('a reader in no Groups has an empty Circle', () async {
      final circle = await circleService.fetchCircleMemberIds('u1');
      expect(circle, isEmpty);
    });

    test('leaving a Group removes its members from the Circle', () async {
      await seedGroup(
        id: 'g1',
        ownerUid: 'u1',
        members: [
          {'uid': 'u2', 'role': 'member'},
        ],
      );
      await seedGroup(
        id: 'g2',
        ownerUid: 'u3',
        members: [
          {'uid': 'u2', 'role': 'member'},
        ],
      );

      await firestore
          .collection('groups')
          .doc('g1')
          .collection('members')
          .doc('u2')
          .delete();

      final circle = await circleService.fetchCircleMemberIds('u2');
      expect(circle, {'u3'});
    });
  });

  group('CircleService.watchCircleMembers', () {
    test('emits empty list when reader is in no groups', () async {
      final future = nextWhere<List<CircleMember>>(
        circleService.watchCircleMembers('u1'),
        (members) => true,
      );

      final members = await future.timeout(const Duration(seconds: 3));
      expect(members, isEmpty);
    });

    test('emits circle members with deduplication and aggregated groupIds',
        () async {
      await seedGroup(
        id: 'g1',
        ownerUid: 'u1',
        members: [
          {'uid': 'u2', 'name': 'User Two', 'photoUrl': 'https://photo/2'},
        ],
      );
      await seedGroup(
        id: 'g2',
        ownerUid: 'u3',
        members: [
          {'uid': 'u2', 'name': 'User Two'},
          {'uid': 'u4', 'name': 'User Four'},
        ],
      );

      final future = nextWhere<List<CircleMember>>(
        circleService.watchCircleMembers('u2'),
        (members) => members.length == 3,
      );

      final members = await future.timeout(const Duration(seconds: 3));
      final byUid = {for (final m in members) m.uid: m};

      expect(byUid.containsKey('u1'), isTrue);
      expect(byUid['u1']!.groupIds, {'g1'});

      expect(byUid.containsKey('u3'), isTrue);
      expect(byUid['u3']!.groupIds, {'g2'});

      expect(byUid.containsKey('u4'), isTrue);
      expect(byUid['u4']!.groupIds, {'g2'});

      // The reader themselves (u2) must be excluded
      expect(byUid.containsKey('u2'), isFalse);
    });

    test('aggregates groupIds when co-member is in multiple shared groups',
        () async {
      // u1 and u2 are together in both g1 and g2
      await seedGroup(
        id: 'g1',
        ownerUid: 'u1',
        members: [
          {'uid': 'u2', 'role': 'member'},
        ],
      );
      await seedGroup(
        id: 'g2',
        ownerUid: 'u1',
        members: [
          {'uid': 'u2', 'role': 'member'},
        ],
      );

      final future = nextWhere<List<CircleMember>>(
        circleService.circleMembers('u2'), // test alias
        (members) =>
            members.any((m) => m.uid == 'u1' && m.groupIds.length == 2),
      );

      final members = await future.timeout(const Duration(seconds: 3));
      final u1 = members.firstWhere((m) => m.uid == 'u1');
      expect(u1.groupIds, {'g1', 'g2'});
    });

    test('circleMembers stream emits when a new member joins', () async {
      await seedGroup(
        id: 'g1',
        ownerUid: 'u1',
        members: [
          {'uid': 'u2', 'role': 'member'},
        ],
      );

      final joined = nextWhere<List<CircleMember>>(
        circleService.watchCircleMembers('u2'),
        (members) => members.any((member) => member.uid == 'u3'),
      );

      await firestore
          .collection('groups')
          .doc('g1')
          .collection('members')
          .doc('u3')
          .set({'uid': 'u3', 'name': 'User 3', 'role': 'member'});

      final circle = await joined.timeout(const Duration(seconds: 3));
      expect(circle.map((member) => member.uid), contains('u3'));
      final u3 = circle.firstWhere((m) => m.uid == 'u3');
      expect(u3.name, 'User 3');
      expect(u3.groupIds, {'g1'});
    });
  });

  group('CircleService.memberCompletedDates', () {
    test('emits completed date keys where count > 0 or done == true', () async {
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('progress')
          .doc('2026-10-14')
          .set({'dummy': true});
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('progress')
          .doc('2026-10-14')
          .collection('entries')
          .doc('u1')
          .set({'count': 1, 'done': true});

      await firestore
          .collection('groups')
          .doc('g1')
          .collection('progress')
          .doc('2026-10-15')
          .set({'dummy': true});
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('progress')
          .doc('2026-10-15')
          .collection('entries')
          .doc('u1')
          .set({'count': 0, 'done': true});

      await firestore
          .collection('groups')
          .doc('g1')
          .collection('progress')
          .doc('2026-10-16')
          .set({'dummy': true});
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('progress')
          .doc('2026-10-16')
          .collection('entries')
          .doc('u1')
          .set({'count': 0, 'done': false});

      final future = nextWhere<Set<String>>(
        circleService.memberCompletedDates('g1', 'u1'),
        (dates) => dates.contains('2026-10-14') && dates.contains('2026-10-15'),
      );

      final completed = await future.timeout(const Duration(seconds: 3));
      expect(completed, contains('2026-10-14'));
      expect(completed, contains('2026-10-15'));
      expect(completed.contains('2026-10-16'), isFalse);
    });
  });

  group('Friends (ADR-0012)', () {
    Future<void> seedFriend(
      String uid,
      String friendUid, {
      String? name,
      DateTime? since,
    }) async {
      await firestore
          .collection('users')
          .doc(uid)
          .collection('friendships')
          .doc(friendUid)
          .set({
        'uid': friendUid,
        if (name != null) 'name': name,
        if (since != null) 'since': since,
      });
    }

    test('watch includes a Friend with no shared Group', () async {
      await seedFriend('u1', 'f1', name: 'Mei', since: DateTime(2026, 10, 3));

      final future = nextWhere<List<CircleMember>>(
        circleService.watchCircleMembers('u1'),
        (members) => members.any((m) => m.uid == 'f1'),
      );

      final members = await future.timeout(const Duration(seconds: 3));
      final friend = members.firstWhere((m) => m.uid == 'f1');
      expect(friend.isFriend, isTrue);
      expect(friend.groupIds, isEmpty);
      expect(friend.name, 'Mei');
      expect(friend.friendSince, DateTime(2026, 10, 3));
    });

    test('a Friend who also shares a Group appears once', () async {
      await seedGroup(
        id: 'g1',
        ownerUid: 'u1',
        members: [
          {'uid': 'f1', 'name': 'Mei'},
        ],
      );
      await seedFriend('u1', 'f1', name: 'Mei');

      final future = nextWhere<List<CircleMember>>(
        circleService.watchCircleMembers('u1'),
        (members) => members.any((m) => m.uid == 'f1'),
      );

      final members = await future.timeout(const Duration(seconds: 3));
      final matches = members.where((m) => m.uid == 'f1').toList();
      expect(matches, hasLength(1));
      expect(matches.single.groupIds, {'g1'});
      expect(matches.single.isFriend, isTrue);
    });

    test('Friends work with no Groups', () async {
      await seedFriend('u1', 'f1', name: 'Mei');

      final future = nextWhere<List<CircleMember>>(
        circleService.watchCircleMembers('u1'),
        (members) => members.isNotEmpty,
      );

      final members = await future.timeout(const Duration(seconds: 3));
      expect(members.map((m) => m.uid), {'f1'});
    });

    test('fetchCircleMemberIds includes Friends', () async {
      await seedGroup(
        id: 'g1',
        ownerUid: 'u1',
        members: [
          {'uid': 'u2'},
        ],
      );
      await seedFriend('u1', 'f1');

      expect(await circleService.fetchCircleMemberIds('u1'), {'u2', 'f1'});
    });

    test('an unfriended Friend with no shared Group leaves the Circle',
        () async {
      await seedFriend('u1', 'f1', name: 'Mei');
      final future = nextWhere<List<CircleMember>>(
        circleService.watchCircleMembers('u1'),
        (members) => members.any((m) => m.uid == 'f1'),
      );
      await future.timeout(const Duration(seconds: 3));

      final gone = nextWhere<List<CircleMember>>(
        circleService.watchCircleMembers('u1'),
        (members) => members.every((m) => m.uid != 'f1'),
      );
      await firestore
          .collection('users')
          .doc('u1')
          .collection('friendships')
          .doc('f1')
          .delete();

      expect(
        (await gone.timeout(const Duration(seconds: 3)))
            .where((m) => m.uid == 'f1'),
        isEmpty,
      );
    });

    test('an unfriended Friend who shares a Group stays in the Circle',
        () async {
      await seedGroup(
        id: 'g1',
        ownerUid: 'u1',
        members: [
          {'uid': 'f1', 'name': 'Mei'},
        ],
      );
      await seedFriend('u1', 'f1', name: 'Mei');
      final future = nextWhere<List<CircleMember>>(
        circleService.watchCircleMembers('u1'),
        (members) => members.any((m) => m.isFriend),
      );
      await future.timeout(const Duration(seconds: 3));

      final updated = nextWhere<List<CircleMember>>(
        circleService.watchCircleMembers('u1'),
        (members) => members.any((m) => m.uid == 'f1' && !m.isFriend),
      );
      await firestore
          .collection('users')
          .doc('u1')
          .collection('friendships')
          .doc('f1')
          .delete();

      final member =
          (await updated.timeout(const Duration(seconds: 3))).firstWhere(
        (m) => m.uid == 'f1',
      );
      expect(member.groupIds, {'g1'});
      expect(member.isFriend, isFalse);
    });
  });
}
