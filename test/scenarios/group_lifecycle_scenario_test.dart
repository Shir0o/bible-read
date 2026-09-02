import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:bible_read/pages/create_group_page.dart';
import 'package:bible_read/pages/groups_page.dart';
import 'package:bible_read/widgets/group_plan_keys.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import '../helpers/pump_app.dart';
import '../helpers/firebase_seeder.dart';
import '../helpers/stub_vibration_service.dart';
import '../helpers/fake_google_sign_in_platform.dart';

void main() {
  setUpAll(() {
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();
  });

  testWidgets('Group Lifecycle Scenario: User creates a new group', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      // Setup
      final auth = MockFirebaseAuth(signedIn: false);
      final firestore = FakeFirebaseFirestore();
      final vibration = StubVibrationService();
      final seeder = FirebaseSeeder(firestore);

      // Create services manually
      final notificationService = NotificationService(firestore: firestore);
      final groupService = GroupService(
        firestore: firestore,
        notificationService: notificationService,
      );

      // Seed User
      final userCred = await auth.createUserWithEmailAndPassword(
        email: 'creator@example.com',
        password: 'password',
      );
      final uid = userCred.user!.uid;
      await seeder.seedUser(uid: uid, name: 'Creator');

      // Pump GroupsPage
      await tester.pumpApp(
        GroupsPage(
          auth: auth,
          groupService: groupService,
          vibrationService: vibration,
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Join or Create Group"
      final joinCreateBtn = find.text('Join or Create Group');
      expect(joinCreateBtn, findsOneWidget);
      await tester.tap(joinCreateBtn);
      await tester.pumpAndSettle();

      // Tap "Create New Group"
      final createNewBtn = find.text('Create New Group');
      expect(createNewBtn, findsOneWidget);
      await tester.tap(createNewBtn);
      await tester.pumpAndSettle();

      // Verify CreateGroupPage loaded
      expect(find.byType(CreateGroupPage), findsOneWidget);

      // 1. Search for "Genesis"
      await tester.enterText(
        find.byKey(GroupPlanKeys.bookSearchField),
        'Genesis',
      );
      await tester.pumpAndSettle();

      // 2. Select "Genesis" from the Autocomplete overlay.
      await tester.tap(find.text('Genesis').last);
      await tester.pumpAndSettle();

      // 3. The plan defaults to a chapters-a-day pace, so no date picker is
      //    needed. Raise it a little to check the stepper drives generation.
      await tester.scrollUntilVisible(
        find.byKey(GroupPlanKeys.chaptersPerDayStepper),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(GroupPlanKeys.chaptersPerDayStepper),
          matching: find.byIcon(Icons.add),
        ),
      );
      await tester.pumpAndSettle();

      // 4. Create the plan.
      final createBtn = find.byKey(GroupPlanKeys.submitButton);
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();

      // 5. Verify Success & Navigation
      // Should arrive at GroupDetailPage with "Genesis Plan"
      expect(find.textContaining('Genesis Plan'), findsOneWidget);

      // Verify Firestore Data
      final groups = await firestore.collection('groups').get();
      expect(groups.docs.length, 1);
      final groupData = groups.docs.first.data();
      expect(groupData['name'], contains('Genesis'));
      expect(groupData['ownerUid'], uid);

      // The plan is materialised, starts where it should, and its
      // configuration is stored so editing it later is lossless.
      final schedule = await firestore
          .collection('groups')
          .doc(groups.docs.first.id)
          .collection('schedule')
          .orderBy('date')
          .get();
      expect(schedule.docs, isNotEmpty);
      expect(schedule.docs.first.data()['chapters'].first, 'Genesis 1');
      expect(groupData['planConfig']['startRef'], 'Genesis 1');
      expect(groupData['planConfig']['books'], ['Genesis']);
    });
  });
}
