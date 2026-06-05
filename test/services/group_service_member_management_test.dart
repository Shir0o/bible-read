// Tests for the member-management additions backing issue #724:
// membersWithRoles, pendingInvites, cancelInvite, and transferOwnership.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/services/group_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    const channel = MethodChannel('plugins.flutter.io/firebase_crashlytics');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return null;
    });
    await Firebase.initializeApp();
  });

  group('GroupService member management', () {
    late FakeFirebaseFirestore firestore;
    late GroupService service;
    late DocumentReference<Map<String, dynamic>> groupRef;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      service = GroupService(firestore: firestore);
      groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'owner'});
      await groupRef.collection(GroupCollections.members).doc('owner').set({
        'uid': 'owner',
        'role': 'owner',
        'name': 'Olivia',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
      });
      await groupRef.collection(GroupCollections.members).doc('u2').set({
        'uid': 'u2',
        'role': 'member',
        'name': 'Mona',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 2)),
      });
      await groupRef.collection(GroupCollections.members).doc('u3').set({
        'uid': 'u3',
        'role': 'admin',
        'name': 'Aaron',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 3)),
      });
    });

    test('membersWithRoles sorts owner, admin, then member', () async {
      final members = await service.membersWithRoles('g1').first;
      expect(members.map((m) => m.uid), ['owner', 'u3', 'u2']);
      expect(members.first.role, 'owner');
      expect(members.first.name, 'Olivia');
    });

    test('pendingInvites streams invites newest first', () async {
      await groupRef.collection(GroupCollections.invites).doc('a').set({
        'recipientUid': 'a',
        'timestamp': Timestamp.fromDate(DateTime.utc(2024, 2, 1)),
      });
      await groupRef.collection(GroupCollections.invites).doc('b').set({
        'recipientUid': 'b',
        'timestamp': Timestamp.fromDate(DateTime.utc(2024, 3, 1)),
      });

      final invites = await service.pendingInvites('g1').first;
      expect(invites.map((i) => i.recipientUid), ['b', 'a']);
    });

    test('cancelInvite deletes the invite document', () async {
      await groupRef.collection(GroupCollections.invites).doc('x').set({
        'recipientUid': 'x',
        'timestamp': Timestamp.fromDate(DateTime.utc(2024, 2, 1)),
      });

      await service.cancelInvite(groupId: 'g1', inviteeUid: 'x');

      final snap =
          await groupRef.collection(GroupCollections.invites).doc('x').get();
      expect(snap.exists, isFalse);
    });

    test('transferOwnership rewrites owner and both member roles', () async {
      await service.transferOwnership(
        groupId: 'g1',
        currentOwnerUid: 'owner',
        newOwnerUid: 'u2',
      );

      final group = await groupRef.get();
      expect(group.data()?['ownerUid'], 'u2');

      final newOwner =
          await groupRef.collection(GroupCollections.members).doc('u2').get();
      final oldOwner = await groupRef
          .collection(GroupCollections.members)
          .doc('owner')
          .get();
      expect(newOwner.data()?['role'], 'owner');
      expect(oldOwner.data()?['role'], 'admin');
    });

    test('transferOwnership rejects a non-owner caller', () async {
      await expectLater(
        service.transferOwnership(
          groupId: 'g1',
          currentOwnerUid: 'u3',
          newOwnerUid: 'u2',
        ),
        throwsStateError,
      );
      final group = await groupRef.get();
      expect(group.data()?['ownerUid'], 'owner');
    });

    test('transferOwnership rejects a non-member target', () async {
      await expectLater(
        service.transferOwnership(
          groupId: 'g1',
          currentOwnerUid: 'owner',
          newOwnerUid: 'ghost',
        ),
        throwsStateError,
      );
    });
  });
}
