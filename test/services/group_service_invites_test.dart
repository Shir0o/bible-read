import 'package:bible_read/models/group.dart';
import 'package:bible_read/models/notification_preferences.dart';
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

    test('sendGroupInvite creates invite and notification', () async {
      final groupId = 'group1';
      final groupName = 'Test Group';
      final senderUid = 'owner';
      final senderName = 'Owner Name';
      final recipientUid = 'user1';

      await groupService.sendGroupInvite(
        groupId: groupId,
        groupName: groupName,
        senderUid: senderUid,
        senderName: senderName,
        recipientUid: recipientUid,
      );

      final inviteDoc = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('invites')
          .doc(recipientUid)
          .get();

      expect(inviteDoc.exists, isTrue);
      expect(inviteDoc.data()?['groupName'], equals(groupName));

      final notificationSnap = await firestore
          .collection('users')
          .doc(recipientUid)
          .collection('notifications')
          .get();

      expect(notificationSnap.docs.length, equals(1));
      expect(notificationSnap.docs.first.data()['type'],
          equals(NotificationType.groupInvite.name));
    });

    test('respondToGroupInvite (Accept) adds member and cleans up', () async {
      final groupId = await groupService.createGroup(
        ownerUid: 'owner',
        name: 'Test Group',
      );
      final recipientUid = 'user1';
      
      // Setup invite and notification
      await groupService.sendGroupInvite(
        groupId: groupId,
        groupName: 'Test Group',
        senderUid: 'owner',
        senderName: 'Owner',
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

    test('respondToGroupInvite (Decline) deletes invite and cleans up', () async {
      final groupId = 'group1';
      final recipientUid = 'user1';
      
      await groupService.sendGroupInvite(
        groupId: groupId,
        groupName: 'Test Group',
        senderUid: 'owner',
        senderName: 'Owner',
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
    });
  });
}
