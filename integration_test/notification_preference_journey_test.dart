import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/settings_page.dart';
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

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    // 3. Toggle switch on SettingsPage directly
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

    // 5. Toggle Amens inline in Settings
    final amensText = find.text('Amens');
    await tester.dragUntilVisible(
      amensText,
      find.byType(SingleChildScrollView),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();

    final amensSwitch = find.ancestor(
      of: amensText,
      matching: find.byType(SwitchListTile),
    );
    await tester.tap(amensSwitch);
    await tester.pumpAndSettle();

    final amenDoc = await firestore
        .collection('users')
        .doc('test_user_uid')
        .collection('notificationPrefs')
        .doc('amen')
        .get();
    expect(amenDoc.data()?['enabled'], isFalse);
  });
}
