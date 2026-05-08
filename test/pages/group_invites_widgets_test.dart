import 'package:bible_read/models/group.dart';
import 'package:bible_read/models/group_invite.dart';
import 'package:bible_read/pages/group_detail_page.dart';
import 'package:bible_read/pages/groups_page.dart';
import 'package:bible_read/pages/invite_member_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockGroupService extends Mock implements GroupService {}

class MockFriendService extends Mock implements FriendService {}

void main() {
  late FakeFirebaseFirestore firestore;
  late MockUser user;
  late MockFirebaseAuth auth;
  late MockGroupService groupService;
  late MockFriendService friendService;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    user = MockUser(
      uid: 'user1',
      displayName: 'User One',
      email: 'user1@example.com',
    );
    auth = MockFirebaseAuth(signedIn: true, mockUser: user);
    groupService = MockGroupService();
    friendService = MockFriendService();

    // Default stubs
    when(() => groupService.firestore).thenReturn(firestore);
    when(() => groupService.userInvites(any()))
        .thenAnswer((_) => Stream.value([]));
    when(() => groupService.groupsForUser(any()))
        .thenAnswer((_) => Stream.value([]));
  });

  Widget createWidget(Widget child) {
    return MaterialApp(
      home: child,
    );
  }

  group('GroupDetailPage Widget Tests', () {
    testWidgets('shows Join Group for public group', (tester) async {
      final group = Group(
        id: 'group1',
        name: 'Public Group',
        ownerUid: 'owner',
        isPublic: true,
      );

      when(() => groupService.schedule(any()))
          .thenAnswer((_) => Stream.value([]));
      when(() => groupService.memberDailyCompletion(any(),
          date: any(named: 'date'))).thenAnswer((_) => Stream.value([]));
      when(() => groupService.memberOverallCompletion(any()))
          .thenAnswer((_) => Stream.value([]));

      await tester.pumpWidget(createWidget(GroupDetailPage(
        group: group,
        groupService: groupService,
        auth: auth,
      )));

      expect(find.text('Join Group'), findsOneWidget);
    });

    testWidgets('shows Request to Join for private group', (tester) async {
      final group = Group(
        id: 'group1',
        name: 'Private Group',
        ownerUid: 'owner',
        isPublic: false,
      );

      when(() => groupService.schedule(any()))
          .thenAnswer((_) => Stream.value([]));
      when(() => groupService.memberDailyCompletion(any(),
          date: any(named: 'date'))).thenAnswer((_) => Stream.value([]));
      when(() => groupService.memberOverallCompletion(any()))
          .thenAnswer((_) => Stream.value([]));

      await tester.pumpWidget(createWidget(GroupDetailPage(
        group: group,
        groupService: groupService,
        auth: auth,
      )));

      expect(find.text('Request to Join'), findsOneWidget);
    });
  });

  group('GroupsPage Invitation UI', () {
    testWidgets('shows INVITATIONS section when invites exist', (tester) async {
      final invites = [
        GroupInvite(
          id: 'invite1',
          groupId: 'group1',
          groupName: 'Cool Group',
          senderUid: 'owner',
          senderName: 'Owner Name',
          recipientUid: 'user1',
          timestamp: DateTime.now(),
        ),
      ];

      when(() => groupService.userInvites('user1'))
          .thenAnswer((_) => Stream.value(invites));
      when(() => groupService.groupsForUser('user1'))
          .thenAnswer((_) => Stream.value([]));

      await tester.pumpWidget(createWidget(GroupsPage(
        groupService: groupService,
        auth: auth,
      )));

      await tester.pump(); // Start stream
      await tester.pump(); // Rebuild with data

      expect(find.text('INVITATIONS'), findsOneWidget);
      expect(find.text('Cool Group'), findsOneWidget);
      expect(find.text('Invited by Owner Name'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    });
  });

  group('InviteMemberPage Widget Tests', () {
    testWidgets('shows friends list by default', (tester) async {
      final group = Group(id: 'g1', name: 'G1', ownerUid: 'user1');
      final friends = [
        Friend(uid: 'friend1', name: 'Friend One'),
      ];

      when(() => friendService.friends('user1'))
          .thenAnswer((_) => Stream.value(friends));

      await tester.pumpWidget(createWidget(InviteMemberPage(
        group: group,
        groupService: groupService,
        friendService: friendService,
        auth: auth,
      )));

      await tester.pump(); // Start stream
      await tester.pump(); // Rebuild with data

      expect(find.text('MY FRIENDS'), findsOneWidget);
      expect(find.text('Friend One'), findsOneWidget);
    });

    testWidgets('shows invited status for friends with pending invites',
        (tester) async {
      final group = Group(id: 'g1', name: 'G1', ownerUid: 'user1');
      final friends = [
        Friend(uid: 'friend1', name: 'Friend One'),
      ];

      await firestore
          .collection(GroupCollections.groups)
          .doc('g1')
          .collection(GroupCollections.invites)
          .doc('friend1')
          .set({
        'groupId': 'g1',
        'groupName': 'G1',
        'senderUid': 'user1',
        'senderName': 'User One',
        'recipientUid': 'friend1',
        'timestamp': DateTime.now(),
      });

      when(() => friendService.friends('user1'))
          .thenAnswer((_) => Stream.value(friends));

      await tester.pumpWidget(createWidget(InviteMemberPage(
        group: group,
        groupService: groupService,
        friendService: friendService,
        auth: auth,
      )));

      await tester.pump();
      await tester.pump();

      expect(find.text('Friend One'), findsOneWidget);
      expect(find.text('Invited'), findsOneWidget);
      expect(find.byIcon(Icons.mark_email_read_outlined), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Invite'), findsNothing);
    });

    testWidgets('shows member status for friends already in the group',
        (tester) async {
      final group = Group(id: 'g1', name: 'G1', ownerUid: 'user1');
      final friends = [
        Friend(uid: 'friend1', name: 'Friend One'),
      ];

      await firestore
          .collection(GroupCollections.groups)
          .doc('g1')
          .collection(GroupCollections.members)
          .doc('friend1')
          .set({
        'uid': 'friend1',
        'role': 'member',
        'joinedAt': DateTime.now(),
      });

      when(() => friendService.friends('user1'))
          .thenAnswer((_) => Stream.value(friends));

      await tester.pumpWidget(createWidget(InviteMemberPage(
        group: group,
        groupService: groupService,
        friendService: friendService,
        auth: auth,
      )));

      await tester.pump();
      await tester.pump();

      expect(find.text('Friend One'), findsOneWidget);
      expect(find.text('Member'), findsOneWidget);
      expect(find.byIcon(Icons.verified_user_outlined), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Invite'), findsNothing);
    });
  });
}
