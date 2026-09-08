import 'package:bible_read/services/group_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late GroupService groupService;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    groupService = GroupService(firestore: firestore);
  });

  group('GroupService Invitations & Joins', () {
    test('joinGroup joins directly if group is public', () async {
      final groupId = await groupService.createGroup(
        ownerUid: 'owner',
        name: 'Public Group',
        isPublic: true,
      );

      await groupService.joinGroup(
        groupId: groupId,
        uid: 'user1',
        name: 'User One',
        isPublic: true,
      );

      final memberDoc = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc('user1')
          .get();

      expect(memberDoc.exists, isTrue);

      final groupDoc = await firestore.collection('groups').doc(groupId).get();
      expect(groupDoc.data()?['memberCount'], equals(2)); // Owner + user1
    });

    test('joinGroup creates request if group is private', () async {
      final groupId = await groupService.createGroup(
        ownerUid: 'owner',
        name: 'Private Group',
        isPublic: false,
      );

      await groupService.joinGroup(
        groupId: groupId,
        uid: 'user1',
        name: 'User One',
        isPublic: false,
      );

      final memberDoc = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc('user1')
          .get();
      final requestDoc = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('joinRequests')
          .doc('user1')
          .get();

      expect(memberDoc.exists, isFalse);
      expect(requestDoc.exists, isTrue);
    });

    test(
      'joinGroup does not request access for existing private member',
      () async {
        final groupId = await groupService.createGroup(
          ownerUid: 'owner',
          name: 'Private Group',
          isPublic: false,
        );
        await groupService.joinGroupDirectly(
          groupId: groupId,
          uid: 'user1',
          name: 'User One',
        );

        await groupService.joinGroup(
          groupId: groupId,
          uid: 'user1',
          name: 'User One',
          isPublic: false,
        );

        final requestDoc = await firestore
            .collection('groups')
            .doc(groupId)
            .collection('joinRequests')
            .doc('user1')
            .get();
        final groupDoc =
            await firestore.collection('groups').doc(groupId).get();

        expect(requestDoc.exists, isFalse);
        expect(groupDoc.data()?['memberCount'], equals(2));
      },
    );

    test('respondToGroupInvite (Accept) adds member and cleans up', () async {
      final groupId = await groupService.createGroup(
        ownerUid: 'owner',
        name: 'Test Group',
      );
      final recipientUid = 'user1';

      // Setup invite and notification
      await seedInvite(
        firestore,
        groupId: groupId,
        recipientUid: recipientUid,
      );

      await groupService.respondToGroupInvite(
        groupId: groupId,
        uid: recipientUid,
        name: 'User One',
        accept: true,
      );

      final memberDoc = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(recipientUid)
          .get();
      final inviteDoc = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('invites')
          .doc(recipientUid)
          .get();
      final notificationSnap = await firestore
          .collection('users')
          .doc(recipientUid)
          .collection('notifications')
          .get();

      expect(memberDoc.exists, isTrue);
      expect(inviteDoc.exists, isFalse);
      expect(notificationSnap.docs.isEmpty, isTrue);
    });

    test('respondToGroupInvite cannot accept missing invite', () async {
      final groupId = await groupService.createGroup(
        ownerUid: 'owner',
        name: 'Private Group',
      );

      await expectLater(
        groupService.respondToGroupInvite(
          groupId: groupId,
          uid: 'user1',
          name: 'User One',
          accept: true,
        ),
        throwsStateError,
      );

      final memberDoc = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc('user1')
          .get();
      final groupDoc = await firestore.collection('groups').doc(groupId).get();

      expect(memberDoc.exists, isFalse);
      expect(groupDoc.data()?['memberCount'], equals(1));
    });

    test(
      'respondToGroupInvite (Decline) deletes invite and cleans up',
      () async {
        final groupId = await groupService.createGroup(
          ownerUid: 'owner',
          name: 'Test Group',
        );
        final recipientUid = 'user1';

        await seedInvite(
          firestore,
          groupId: groupId,
          recipientUid: recipientUid,
        );

        await groupService.respondToGroupInvite(
          groupId: groupId,
          uid: recipientUid,
          name: 'User One',
          accept: false,
        );

        final memberDoc = await firestore
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .doc(recipientUid)
            .get();
        final inviteDoc = await firestore
            .collection('groups')
            .doc(groupId)
            .collection('invites')
            .doc(recipientUid)
            .get();

        expect(memberDoc.exists, isFalse);
        expect(inviteDoc.exists, isFalse);
      },
    );

    test('approveJoinRequest cannot approve missing request', () async {
      final groupId = await groupService.createGroup(
        ownerUid: 'owner',
        name: 'Private Group',
      );

      await expectLater(
        groupService.approveJoinRequest(groupId: groupId, uid: 'user1'),
        throwsStateError,
      );

      final memberDoc = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc('user1')
          .get();
      final groupDoc = await firestore.collection('groups').doc(groupId).get();

      expect(memberDoc.exists, isFalse);
      expect(groupDoc.data()?['memberCount'], equals(1));
    });
  });
}

/// Writes an invite document and its notification directly, the way an
/// invite authoring surface would have: [GroupService.sendGroupInvite] was
/// retired with the InviteMemberPage (issue #799), but responding to an
/// invite that already exists remains supported.
Future<void> seedInvite(
  FakeFirebaseFirestore firestore, {
  required String groupId,
  required String recipientUid,
}) async {
  await firestore
      .collection('groups')
      .doc(groupId)
      .collection('invites')
      .doc(recipientUid)
      .set({
    'groupId': groupId,
    'groupName': 'Test Group',
    'senderUid': 'owner',
    'senderName': 'Owner',
    'recipientUid': recipientUid,
    'timestamp': DateTime.now(),
  });
  await firestore
      .collection('users')
      .doc(recipientUid)
      .collection('notifications')
      .doc('groupInvite_${groupId}_owner')
      .set({'type': 'groupInvite', 'groupId': groupId, 'read': false});
}
