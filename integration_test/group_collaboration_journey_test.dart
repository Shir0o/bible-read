import 'package:bible_read/pages/create_group_page.dart';
import 'package:bible_read/pages/group_detail_page.dart';
import 'package:bible_read/pages/groups_page.dart';
import 'package:bible_read/pages/invite_member_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import '../test/helpers/fake_google_sign_in_platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();
    await Firebase.initializeApp();
  });

  testWidgets('Group Collaboration & Scheduling Journey', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final mockUser = MockUser(
      uid: 'owner_uid',
      displayName: 'Owner',
      email: 'owner@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

    // 1. Setup a friend to invite later
    await firestore.collection('users').doc('friend_uid').set({
      'displayName': 'Friend',
      'email': 'friend@example.com',
    });
    // Add to owner's friends list
    await firestore
        .collection('users')
        .doc('owner_uid')
        .collection('friends')
        .doc('friend_uid')
        .set({
      'name': 'Friend',
      'timestamp': FieldValue.serverTimestamp(),
    });

    final friendService = FriendService(firestore: firestore);

    // 2. Launch App
    await tester.pumpWidget(MaterialApp(
      home: MainPage(
        firestore: firestore,
        auth: auth,
        friendService: friendService,
      ),
    ));
    await tester.pumpAndSettle();

    // 3. Navigate to Community and then to Groups
    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('View All').first);
    await tester.pumpAndSettle();
    expect(find.byType(GroupsPage), findsOneWidget);

    // 4. Start Group Creation
    await tester.tap(find.text('Join or Create Group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create New Group'));
    await tester.pumpAndSettle();
    expect(find.byType(CreateGroupPage), findsOneWidget);

    // 5. Configure Group (Select Book: Jude)
    final bookField = find.byType(TextField).first;
    await tester.enterText(bookField, 'Jude');
    await tester.pumpAndSettle();

    // Tap the autocomplete option
    await tester.tap(find.text('Jude').last);
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsOneWidget);

    // Set End Date (select tomorrow to ensure at least one day difference)
    final endDateField = find.text('mm/dd/yyyy');
    await tester.dragUntilVisible(
      endDateField,
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    await tester.tap(endDateField);
    await tester.pumpAndSettle();

    // In the standard Material date picker, "Today" is highlighted.
    // We try to tap the day after today. This is tricky in a generic way.
    // But since we know today is April 18, 2026, we can try to find '19'.
    // Or we just tap OK which selects today, and ensure our normalization fix works.

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // 6. Create Schedule
    final createButton = find.text('Create Schedule');
    await tester.dragUntilVisible(
      createButton,
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    // Allow more time for batch upload and navigation
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify navigation to GroupDetailPage
    expect(find.byType(GroupDetailPage), findsOneWidget);
    expect(find.text('Jude Plan'), findsOneWidget);

    // 7. Invite Friend
    await tester.tap(find.byTooltip('Invite member'));
    await tester.pumpAndSettle();
    expect(find.byType(InviteMemberPage), findsOneWidget);

    // Should see friend in "MY FRIENDS" section
    expect(find.text('Friend'), findsOneWidget);
    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();

    // 8. Verify Firestore State
    final groupsSnap = await firestore.collection('groups').get();
    expect(groupsSnap.docs.length, 1);
    final groupData = groupsSnap.docs.first.data();
    expect(groupData['name'], 'Jude Plan');
    expect(groupData['ownerUid'], 'owner_uid');

    final groupId = groupsSnap.docs.first.id;
    final scheduleSnap = await firestore
        .collection('groups')
        .doc(groupId)
        .collection('schedule')
        .get();
    expect(scheduleSnap.docs.isNotEmpty, isTrue);

    final invitesSnap = await firestore
        .collection('groups')
        .doc(groupId)
        .collection('invites')
        .get();
    expect(invitesSnap.docs.length, 1);
    expect(invitesSnap.docs.first.id, 'friend_uid');

    final userInviteSnap = await firestore
        .collection('users')
        .doc('friend_uid')
        .collection('notifications')
        .get();
    expect(userInviteSnap.docs.length, 1);
  });
}
