import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:bible_read/pages/groups_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:network_image_mock/network_image_mock.dart';
import '../helpers/pump_app.dart';
import '../helpers/firebase_seeder.dart';
import '../helpers/stub_vibration_service.dart';

void main() {
  testWidgets('Group Lifecycle Scenario: User creates a new group',
      (tester) async {
    await mockNetworkImagesFor(() async {
      // Setup
      final auth = MockFirebaseAuth(signedIn: false);
      final firestore = FakeFirebaseFirestore();
      final vibration = StubVibrationService();
      final seeder = FirebaseSeeder(firestore);

      // Create services manually
      final notificationService = NotificationService(firestore: firestore);
      final groupService = GroupService(
          firestore: firestore, notificationService: notificationService);

      // Seed User
      final userCred = await auth.createUserWithEmailAndPassword(
          email: 'creator@example.com', password: 'password');
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
      expect(find.text('New Group Plan'), findsOneWidget);

      // 1. Enter Book Name "Genesis"
      final textField = find.byType(TextField).first;
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'Genesis');
      await tester.pumpAndSettle();

      // 2. Select "Genesis" from Autocomplete options
      // Note: Autocomplete options are in a separate overlay.
      final genesisOption = find.text('Genesis').last;
      await tester.tap(genesisOption);
      await tester.pumpAndSettle();

      // 3. Select End Date
      // We look for the mm/dd/yyyy text or calendar icon.
      // Based on typical UI code, mm/dd/yyyy is shown when date is null.
      final datePickerTrigger = find.text('mm/dd/yyyy');
      if (datePickerTrigger.evaluate().isNotEmpty) {
        await tester.tap(datePickerTrigger.last);
      } else {
        // Fallback to icon if text changed
        await tester.tap(find.byIcon(Icons.calendar_today).last);
      }
      await tester.pumpAndSettle();

      // Select date (e.g., 28)
      await tester.tap(find.text('28'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // 4. Tap "Create Schedule"
      final createBtn = find.text('Create Schedule');
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
    });
  });
}
