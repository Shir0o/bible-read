import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/services/group_service.dart';

// The Circle is derived from Group membership at read time (ADR-0003,
// #795): everyone the reader shares at least one Group with. There is no
// stored circle collection, a person in several Groups appears once, and
// the reader themselves is not part of their own Circle.
void main() {
  late FakeFirebaseFirestore firestore;
  late GroupService groupService;

  Future<String> seedGroup({
    required String id,
    required String ownerUid,
    List<String> members = const [],
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
    for (final uid in members) {
      await firestore
          .collection('groups')
          .doc(id)
          .collection('members')
          .doc(uid)
          .set({'uid': uid, 'role': 'member'});
    }
    return id;
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    groupService = GroupService(firestore: firestore);
  });

  test('derives co-members from the groups the reader belongs to', () async {
    await seedGroup(id: 'g1', ownerUid: 'u1', members: ['u2', 'u3']);

    final circle = await groupService.circleMemberIds('u2');

    expect(circle, {'u1', 'u3'});
  });

  test('a person shared by two Groups appears once', () async {
    await seedGroup(id: 'g1', ownerUid: 'u1', members: ['u2']);
    await seedGroup(id: 'g2', ownerUid: 'u3', members: ['u2']);

    final circle = await groupService.circleMemberIds('u2');

    expect(circle, {'u1', 'u3'});
  });

  test('the reader is not part of their own Circle', () async {
    await seedGroup(id: 'g1', ownerUid: 'u1', members: ['u2', 'u3']);

    final circle = await groupService.circleMemberIds('u1');

    expect(circle, {'u2', 'u3'});
  });

  test('a reader in no Groups has an empty Circle', () async {
    final circle = await groupService.circleMemberIds('u1');

    expect(circle, isEmpty);
  });

  test('leaving a Group removes its members from the Circle', () async {
    await seedGroup(id: 'g1', ownerUid: 'u1', members: ['u2']);
    await seedGroup(id: 'g2', ownerUid: 'u3', members: ['u2']);

    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u2')
        .delete();

    final circle = await groupService.circleMemberIds('u2');

    expect(circle, {'u3'});
  });
}
