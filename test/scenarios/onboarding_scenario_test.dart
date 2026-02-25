import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/welcome_page.dart';
import 'package:bible_read/pages/login_page.dart';
import 'package:bible_read/pages/home_page.dart';
import 'package:google_sign_in_mocks/google_sign_in_mocks.dart';
import 'package:mocktail/mocktail.dart';
import 'package:network_image_mock/network_image_mock.dart';
import '../helpers/pump_app.dart';
import '../helpers/firebase_seeder.dart';
import '../helpers/mocks.dart';
import '../helpers/stub_vibration_service.dart';

void main() {
  testWidgets('Onboarding Scenario: User launches app, sees welcome, logs in, lands on home',
      (tester) async {
    await mockNetworkImagesFor(() async {
      // Setup
      final auth = MockFirebaseAuth(signedIn: false);
      final firestore = FakeFirebaseFirestore();
      final messaging = MockFirebaseMessaging();
      final functions = MockFirebaseFunctions();
      final vibration = StubVibrationService();
      final seeder = FirebaseSeeder(firestore);

      // Stub messaging
      when(() => messaging.getToken()).thenAnswer((_) async => 'fake_token');

      // Create user in Auth (but ensure signed out initially)
      await auth.createUserWithEmailAndPassword(
          email: 'test@example.com', password: 'password123');
      await auth.signOut();

      // Seed Firestore user data
      await auth.signInWithEmailAndPassword(
          email: 'test@example.com', password: 'password123');
      final uid = auth.currentUser!.uid;
      await auth.signOut();
      await seeder.seedUser(
          uid: uid, email: 'test@example.com', name: 'Test User');

      await tester.pumpApp(
        MainPage(
          auth: auth,
          firestore: firestore,
          messaging: messaging,
          functions: functions,
          sendLikeNotification: ({required ownerUid, required likerName}) async {},
          sendCommentNotification: ({required ownerUid,
              required commenterName}) async {},
          vibrationService: vibration,
          googleSignInProvider: () => MockGoogleSignIn(),
        ),
      );
      await tester.pumpAndSettle();

      // Check if stuck on loading
      if (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
        // Force a pump
        await tester.pump(const Duration(seconds: 1));
      }

      // Verify Welcome Page
      expect(find.byType(WelcomePage), findsOneWidget);

      // Tap "I already have an account"
      await tester.tap(find.text('I already have an account'));
      await tester.pumpAndSettle();

      // Verify Login Page
      expect(find.byType(LoginPage), findsOneWidget);

      // Enter credentials
      await tester.enterText(
          find.byKey(const Key('loginEmailField')), 'test@example.com');
      await tester.enterText(
          find.byKey(const Key('loginPasswordField')), 'password123');
      await tester.pump();

      // Tap Login Button
      await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
      await tester.pump();

      // Wait for auth
      await tester.pumpAndSettle();

      // Set display name in Auth after login (since MockUser from login won't have it)
      await auth.currentUser!.updateDisplayName('Test User');
      await tester.pump();

      // Verify Home Page
      expect(find.byType(HomePage), findsOneWidget);
      await tester.pumpAndSettle();

      // Navigate to Community where user name is displayed
      await tester.tap(find.text('Community'));
      await tester.pumpAndSettle();

      // Verify user is displayed
      expect(find.textContaining('Test'), findsOneWidget);
    });
  });
}
