import 'package:bible_read/models/group.dart';
import 'package:bible_read/pages/edit_group_page.dart';
import 'package:bible_read/pages/group_detail_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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

  group('GroupDetailPage Widget Tests', () {
    testWidgets('shows Join Group for public group', (tester) async {
      final group = Group(
        id: 'group1',
        name: 'Public Group',
        ownerUid: 'owner',
        isPublic: true,
      );

      when(
        () => groupService.schedule(any()),
      ).thenAnswer((_) => Stream.value([]));
      when(
        () =>
            groupService.memberDailyCompletion(any(), date: any(named: 'date')),
      ).thenAnswer((_) => Stream.value([]));
      when(
        () => groupService.memberOverallCompletion(any()),
      ).thenAnswer((_) => Stream.value([]));

      await tester.pumpWidget(
        createWidget(
          GroupDetailPage(group: group, groupService: groupService, auth: auth),
        ),
      );

      expect(find.text('Join Group'), findsOneWidget);
    });

    testWidgets('shows Request to Join for private group', (tester) async {
      final group = Group(
        id: 'group1',
        name: 'Private Group',
        ownerUid: 'owner',
        isPublic: false,
      );

      when(
        () => groupService.schedule(any()),
      ).thenAnswer((_) => Stream.value([]));
      when(
        () =>
            groupService.memberDailyCompletion(any(), date: any(named: 'date')),
      ).thenAnswer((_) => Stream.value([]));
      when(
        () => groupService.memberOverallCompletion(any()),
      ).thenAnswer((_) => Stream.value([]));

      await tester.pumpWidget(
        createWidget(
          GroupDetailPage(group: group, groupService: groupService, auth: auth),
        ),
      );

      expect(find.text('Request to Join'), findsOneWidget);
    });
  });

  group('InviteMemberPage retirement', () {
    testWidgets('admin invite affordance is gone from GroupDetailPage', (
      tester,
    ) async {
      final group = Group(
        id: 'group1',
        name: 'Owner Group',
        ownerUid: 'user1',
      );

      when(
        () => groupService.schedule(any()),
      ).thenAnswer((_) => Stream.value([]));
      when(
        () =>
            groupService.memberDailyCompletion(any(), date: any(named: 'date')),
      ).thenAnswer((_) => Stream.value([]));
      when(
        () => groupService.memberOverallCompletion(any()),
      ).thenAnswer((_) => Stream.value([]));

      await tester.pumpWidget(
        createWidget(
          GroupDetailPage(group: group, groupService: groupService, auth: auth),
        ),
      );

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
