import 'package:bible_read/pages/general_settings_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/notification_settings_page.dart';
import 'package:bible_read/pages/user_profile_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import '../test/helpers/fake_google_sign_in_platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  testWidgets('Notification & Preference Persistence Journey', (tester) async {
    final google = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = google;

    final firestore = FakeFirebaseFirestore();
    final mockUser = MockUser(
      uid: 'test_user_uid',
      displayName: 'Test User',
      email: 'test@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

    // Initialize with default preferences in Firestore
    await firestore
        .collection('users')
        .doc('test_user_uid')
        .collection('settings')
        .doc('general')
        .set({'autoMarkPlanRead': false});

    await firestore
        .collection('users')
        .doc('test_user_uid')
        .collection('notificationPrefs')
        .doc('like')
        .set({'enabled': false});

    await firestore
        .collection('users')
        .doc('test_user_uid')
        .collection('notificationPrefs')
        .doc('vibration')
        .set({'enabled': false});

    // 1. Launch App
    await tester.pumpWidget(MaterialApp(
      home: MainPage(
        firestore: firestore,
        auth: auth,
      ),
    ));
    await tester.pumpAndSettle();

    // 2. Navigate to Profile via Side Menu
    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.byType(UserProfilePage), findsOneWidget);

    // 3. Navigate to General Settings and Toggle
    await tester.tap(find.text('General Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(GeneralSettingsPage), findsOneWidget);

    final autoMarkSwitch = find.byType(Switch).first;
    expect(tester.widget<Switch>(autoMarkSwitch).value, isFalse);

    await tester.tap(autoMarkSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(autoMarkSwitch).value, isTrue);

    // Verify Firestore updated for general settings
    final generalDoc = await firestore
        .collection('users')
        .doc('test_user_uid')
        .collection('settings')
        .doc('general')
        .get();
    expect(generalDoc.data()?['autoMarkPlanRead'], isTrue);

    // 4. Back to Profile
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 5. Navigate to Notification Settings and Toggle
    await tester.tap(find.text('Notification Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationSettingsPage), findsOneWidget);

    // Wait for loading to finish
    int timeout = 0;
    while (find.byType(CircularProgressIndicator).evaluate().isNotEmpty &&
        timeout < 10) {
      await tester.pump(const Duration(milliseconds: 500));
      timeout++;
    }

    // Toggle Like Notifications
    final likeText = find.text('Like Notifications');
    await tester.dragUntilVisible(
      likeText,
      find.byType(ListView),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();

    final likeSwitch = find.ancestor(
      of: likeText,
      matching: find.byType(SwitchListTile),
    );
    expect(tester.widget<SwitchListTile>(likeSwitch).value, isFalse);
    await tester.tap(likeSwitch);
    await tester.pumpAndSettle();

    // Verify Firestore updated for like notification
    final likeDoc = await firestore
        .collection('users')
        .doc('test_user_uid')
        .collection('notificationPrefs')
        .doc('like')
        .get();
    expect(likeDoc.data()?['enabled'], isTrue);

    // Toggle Vibration
    final vibrationText = find.text('Vibration');
    await tester.dragUntilVisible(
      vibrationText,
      find.byType(ListView),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();

    final vibrationSwitch = find.ancestor(
      of: vibrationText,
      matching: find.byType(SwitchListTile),
    );
    expect(tester.widget<SwitchListTile>(vibrationSwitch).value, isFalse);
    await tester.tap(vibrationSwitch);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(tester.widget<SwitchListTile>(vibrationSwitch).value, isTrue);

    // Verify Firestore updated for vibration
    final vibrationDoc = await firestore
        .collection('users')
        .doc('test_user_uid')
        .collection('notificationPrefs')
        .doc('vibration')
        .get();
    expect(vibrationDoc.data()?['enabled'], isTrue);
  });
}
