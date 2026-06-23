import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/group_detail_page.dart';
import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/models/group_schedule.dart';
import 'package:google_sign_in_mocks/google_sign_in_mocks.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:network_image_mock/network_image_mock.dart';
import '../helpers/pump_app.dart';
import '../helpers/firebase_seeder.dart';
import '../helpers/mocks.dart';
import '../helpers/stub_vibration_service.dart';
import '../helpers/fake_google_sign_in_platform.dart';

void main() {
  setUpAll(() {
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();
  });

  testWidgets('Reading Scenario: User opens group and sees today\'s reading', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final auth = MockFirebaseAuth(signedIn: false);
      final firestore = FakeFirebaseFirestore();
      final messaging = MockFirebaseMessaging();
      final functions = MockFirebaseFunctions();
      final vibration = StubVibrationService();
      final seeder = FirebaseSeeder(firestore);

      // Stub messaging
      when(() => messaging.getToken()).thenAnswer((_) async => 'fake_token');

      // Create user and get UID
      final cred = await auth.createUserWithEmailAndPassword(
        email: 'reader@example.com',
        password: 'password',
      );
      final uid = cred.user!.uid;
      await auth.signOut();

      // Seed user and group
      await seeder.seedUser(uid: uid, name: 'Reader');
      final groupId = 'g1';
      await seeder.seedGroup(
        groupId: groupId,
        ownerUid: uid,
        members: [uid],
        name: 'Reading Group',
      );

      // Seed group schedule for today
      final today = DateTime.now();
      await seeder.seedGroupSchedule(
        groupId: groupId,
        schedule: [
          GroupSchedule(
            date: DateTime(today.year, today.month, today.day),
            chapters: ['Gen 1'],
          ),
        ],
      );

      // Seed ReadingPlan
      await seeder.seedReadingPlan(
        planId: 'plan1',
        name: 'Test Plan',
        chaptersPerDay: 1,
      );

      final now = DateTime.now();
      await firestore.collection('groups').doc(groupId).update({
        'startDate': Timestamp.fromDate(DateTime(now.year, now.month, now.day)),
      });

      await tester.pumpApp(
        MainPage(
          auth: auth,
          firestore: firestore,
          messaging: messaging,
          functions: functions,
          sendLikeNotification: (
              {required ownerUid, required likerName}) async {},
          sendCommentNotification: (
              {required ownerUid, required commenterName}) async {},
          vibrationService: vibration,
          googleSignInProvider: () => MockGoogleSignIn(),
        ),
      );
      await tester.pumpAndSettle();

      // Login via UI
      await tester.tap(find.text('I already have an account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('loginEmailField')),
        'reader@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('loginPasswordField')),
        'password',
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
      await tester.pumpAndSettle();

      // Set display name in Auth after login (since MockUser from login won't have it)
      await auth.currentUser!.updateDisplayName('Reader');
      await tester.pump();

      // Verify HomePage is shown
      expect(find.byType(HomePage), findsOneWidget);

      // Navigate to Community
      await tester.tap(find.text('Community'));
      await tester.pumpAndSettle();

      // Open the groups page via "Manage" in the "Your reading groups" section.
      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();

      // Verify group is listed
      expect(find.text('Reading Group'), findsOneWidget);

      // Tap group
      await tester.tap(find.text('Reading Group'));
      await tester.pumpAndSettle();

      // Verify GroupDetailPage
      expect(find.byType(GroupDetailPage), findsOneWidget);
      await tester.pumpAndSettle();

      // Verify "Gen 1" is displayed
      expect(find.textContaining('Gen 1'), findsOneWidget);
    });
  });
}
