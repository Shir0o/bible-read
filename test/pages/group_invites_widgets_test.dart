import 'package:bible_read/models/group.dart';
import 'package:bible_read/pages/edit_group_page.dart';
import 'package:bible_read/pages/group_members_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/nudge_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import '../helpers/stub_vibration_service.dart';

class MockGroupService extends Mock implements GroupService {}

void main() {
  late FakeFirebaseFirestore firestore;
  late MockUser user;
  late MockFirebaseAuth auth;
  late MockGroupService groupService;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    user = MockUser(
      uid: 'user1',
      displayName: 'User One',
      email: 'user1@example.com',
    );
    auth = MockFirebaseAuth(signedIn: true, mockUser: user);
    groupService = MockGroupService();

    // Default stubs
    when(() => groupService.firestore).thenReturn(firestore);
    when(
      () => groupService.userInvites(any()),
    ).thenAnswer((_) => Stream.value([]));
    when(
      () => groupService.groupsForUser(any()),
    ).thenAnswer((_) => Stream.value([]));
  });

  Widget createWidget(Widget child) {
    return MaterialApp(home: child);
  }

  GroupMembersPage buildMembersPage(Group group) => GroupMembersPage(
        group: group,
        groupService: groupService,
        nudgeService: NudgeService(firestore: firestore),
        auth: auth,
        vibrationService: const StubVibrationService(),
      );

  group('GroupMembersPage Widget Tests', () {
    testWidgets('renders Members heading for a public group', (tester) async {
      final group = Group(
        id: 'group1',
        name: 'Public Group',
        ownerUid: 'owner',
        isPublic: true,
      );

      when(
        () => groupService.membersWithRoles(any()),
      ).thenAnswer((_) => Stream.value([]));
      when(
        () =>
            groupService.memberDailyCompletion(any(), date: any(named: 'date')),
      ).thenAnswer((_) => Stream.value([]));
      when(
        () => groupService.pendingInvites(any()),
      ).thenAnswer((_) => Stream.value([]));

      await tester.pumpWidget(createWidget(buildMembersPage(group)));
      await tester.pump();

      expect(find.textContaining('Members'), findsAtLeastNWidgets(1));
    });

    testWidgets('renders Members heading for a private group', (tester) async {
      final group = Group(
        id: 'group1',
        name: 'Private Group',
        ownerUid: 'owner',
        isPublic: false,
      );

      when(
        () => groupService.membersWithRoles(any()),
      ).thenAnswer((_) => Stream.value([]));
      when(
        () =>
            groupService.memberDailyCompletion(any(), date: any(named: 'date')),
      ).thenAnswer((_) => Stream.value([]));
      when(
        () => groupService.pendingInvites(any()),
      ).thenAnswer((_) => Stream.value([]));

      await tester.pumpWidget(createWidget(buildMembersPage(group)));
      await tester.pump();

      expect(find.textContaining('Members'), findsAtLeastNWidgets(1));
    });
  });

  group('InviteMemberPage retirement', () {
    testWidgets('admin invite affordance is gone from GroupMembersPage', (
      tester,
    ) async {
      final group = Group(
        id: 'group1',
        name: 'Owner Group',
        ownerUid: 'user1',
      );

      when(
        () => groupService.membersWithRoles(any()),
      ).thenAnswer((_) => Stream.value([]));
      when(
        () =>
            groupService.memberDailyCompletion(any(), date: any(named: 'date')),
      ).thenAnswer((_) => Stream.value([]));
      when(
        () => groupService.pendingInvites(any()),
      ).thenAnswer((_) => Stream.value([]));

      await tester.pumpWidget(createWidget(buildMembersPage(group)));

      await tester.pump();
      await tester.pump();

      expect(find.byTooltip('Invite member'), findsNothing);
      expect(find.byIcon(Icons.person_add_alt_1), findsNothing);
    });

    testWidgets('Copy Link is gone from EditGroupPage', (tester) async {
      when(
        () => groupService.schedule(any()),
      ).thenAnswer((_) => Stream.value([]));
      when(
        () => groupService.memberOverallCompletion(any()),
      ).thenAnswer((_) => Stream.value([]));

      await tester.pumpWidget(
        createWidget(
          EditGroupPage(
            group: const Group(id: 'g1', name: 'G1', ownerUid: 'user1'),
            groupService: groupService,
            auth: auth,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Copy Link'), findsNothing);
    });
  });
}
