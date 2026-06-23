import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/services/google_sign_in_factory.dart';
import '../test/helpers/fake_google_sign_in_platform.dart';
import 'helpers/screenshot_helper.dart';

void main() {
  initScreenshotBinding();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('navigate between pages', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    final google = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = google;

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          firestore: firestore,
          auth: auth,
          googleSignInProvider: createGoogleSignIn,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify HomePage is showing Today's Reading (or Daily Reading if no plan)
    expect(find.textContaining('Reading'), findsAtLeast(1));
    await takeScreenshot(tester, '01_home_tab');

    // Tap Community tab
    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle();
    expect(find.text('Community'), findsWidgets);
    await takeScreenshot(tester, '02_community_tab');

    // Tap Journey tab
    await tester.tap(find.text('Journey'));
    await tester.pumpAndSettle();
    expect(find.text('My Personal Journey'), findsOneWidget);
    await takeScreenshot(tester, '03_journey_tab');

    // Tap Home tab
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);

    // Open Menu via Profile Avatar on Community page (since HomePage might not have a direct menu button in this setup)
    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle();

    // Find the avatar button which has the 'Open menu' tooltip
    final menuButton = find.byTooltip('Open menu');
    expect(menuButton, findsOneWidget);
    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    // Verify some menu items
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Challenges'), findsOneWidget);
    expect(find.text('Friends'), findsOneWidget);

    // Tap Friends in menu
    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();
    expect(find.text('Friends'), findsAtLeast(1));
  });
}
