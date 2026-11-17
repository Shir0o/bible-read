import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/settings_page.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/app_menu_sheet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  Future<void> openSheet(
    WidgetTester tester, {
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    VibrationService? vibration,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => AppMenuSheet.show(
                context: context,
                vibrationService: vibration ?? const VibrationService(),
                auth: auth,
                firestore: firestore,
              ),
              child: const Text('Open menu'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();
  }

  MockFirebaseAuth signedInAuth() => MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1', displayName: 'Test User'),
        signedIn: true,
      );

  testWidgets('shows profile, Settings, and no retired destinations', (
    tester,
  ) async {
    final auth = signedInAuth();
    final firestore = FakeFirebaseFirestore();
    await openSheet(tester, auth: auth, firestore: firestore);

    expect(find.text('Test User'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    for (final gone in [
      'Challenges',
      'Library',
      'Feedback',
      'History',
      'Sign out',
      'Inbox',
      'Notifications',
    ]) {
      expect(find.text(gone), findsNothing, reason: '"$gone" should be gone');
    }
  });

  testWidgets('shows the streak line from the summary doc', (tester) async {
    final auth = signedInAuth();
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({'streak': 12});
    await openSheet(tester, auth: auth, firestore: firestore);

    expect(find.text('12-day streak'), findsOneWidget);
  });

  testWidgets('Settings opens the settings page', (tester) async {
    final auth = signedInAuth();
    final firestore = FakeFirebaseFirestore();
    await openSheet(tester, auth: auth, firestore: firestore);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.byType(AppMenuSheet), findsNothing);
    expect(find.byType(SettingsPage), findsOneWidget);
  });
}
