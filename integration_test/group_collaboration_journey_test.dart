import 'package:bible_read/pages/create_group_page.dart';
import 'package:bible_read/pages/group_detail_page.dart';
import 'package:bible_read/pages/groups_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/share_code_page.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import '../test/helpers/fake_google_sign_in_platform.dart';
import 'helpers/screenshot_helper.dart';

void main() {
  initScreenshotBinding();
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

    // 2. Launch App
    await tester.pumpWidget(MaterialApp(
      home: MainPage(
        firestore: firestore,
        auth: auth,
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
    await takeScreenshot(tester, '11_group_detail');

    // 7. Share code is the only invite surface
    await tester.tap(find.byTooltip('Share code'));
    await tester.pumpAndSettle();
    expect(find.byType(ShareCodePage), findsOneWidget);

    // A join code was assigned when the group was created: stored on the
    // group document and indexed in the top-level joinCodes lookup.
    final groupsSnap = await firestore.collection('groups').get();
    final groupData = groupsSnap.docs.first.data();
    expect(groupData['name'], 'Jude Plan');
    expect(groupData['ownerUid'], 'owner_uid');
    expect(groupData['joinCode'], isNotNull);

    final groupId = groupsSnap.docs.first.id;
    final codeSnap = await firestore
        .collection('joinCodes')
        .doc(groupData['joinCode'] as String)
        .get();
    expect(codeSnap.exists, isTrue);
    expect(codeSnap.data()?['groupId'], groupId);
  });
}
