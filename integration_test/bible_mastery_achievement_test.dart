import 'package:bible_read/main.dart' as app;
import 'package:bible_read/pages/bible_progress_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/user_profile_page.dart';
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

  testWidgets('Bible Book Mastery & Badge Achievement Journey', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'alice_uid',
        displayName: 'Alice',
        email: 'alice@example.com',
      ),
      signedIn: true,
    );

    // Setup Alice document
    await firestore.collection('users').doc('alice_uid').set({
      'name': 'Alice',
      'email': 'alice@example.com',
    });

    // 1. Launch App
    await tester.pumpWidget(app.MyApp(
      appCheckFailed: false,
      firestore: firestore,
      auth: auth,
    ));
    await tester.pumpAndSettle();
    // 2. Navigate to Journey -> Bible Progress
    final journeyTab = find.text('Journey');
    if (tester.any(journeyTab)) {
      await tester.tap(journeyTab.last);
    } else {
      // Index based fallback
      final mainPageState = tester.state<MainPageState>(find.byType(MainPage));
      mainPageState.onItemTapped(2);
    }
    await tester.pumpAndSettle();

    // Wait for SkeletonLoader in BibleLibraryGrid
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await tester.tap(find.text('See All').last);
    await tester.pumpAndSettle();

    // Verify we are on BibleProgressPage
    expect(find.byType(BibleProgressPage), findsOneWidget);

    // 3. Complete a book (Jude) programmatically to avoid scroll issues
    final progressState =
        tester.state<BibleProgressPageState>(find.byType(BibleProgressPage));
    progressState.handleBookTap('Jude', false);
    await tester.pumpAndSettle();

    // Confirm completion
    expect(find.textContaining('Complete Jude?'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // Verify Jude is marked as completed
    expect(find.text('Jud'), findsAtLeast(1));

    // 4. Verify Achievement is written to Firestore
    final achievementDoc = await firestore
        .collection('users')
        .doc('alice_uid')
        .collection('achievements')
        .doc('nt_starter')
        .get();
    expect(achievementDoc.exists, isTrue);
    expect(achievementDoc.data()?['title'], 'NT Starter');

    // 5. Navigate to Profile and verify Badge is displayed
    // BibleProgressPage was pushed, so we need to pop it first to get back to MainPage
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Now we are back on Journey tab of MainPage.
    // The menu button (profile icon) is visible on Journey tab but hidden on Home tab.

    // Open menu
    // On Journey tab, AppHeader should have the profile icon which acts as menu trigger
    final menuButton = find.byTooltip('Open menu');

    if (tester.any(menuButton)) {
      await tester.tap(menuButton.last);
    } else {
      // Fallback
      final profileIcon = find.byIcon(Icons.person);
      if (tester.any(profileIcon)) {
        await tester.tap(profileIcon.last);
      } else {
        await tester.tap(find.byType(InkWell).last);
      }
    }

    // Wait for bottom sheet animation
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Tap Profile
    final profileItem = find.text('Profile');
    expect(profileItem, findsOneWidget);
    await tester.tap(profileItem);
    await tester.pumpAndSettle();

    // Verify on UserProfilePage
    expect(find.byType(UserProfilePage), findsOneWidget);
    expect(find.text('Achievements'), findsOneWidget);

    // Verify the badge is visible
    expect(find.text('NT Starter'), findsOneWidget);
    await takeScreenshot(tester, '07_mastery_badge');
  });
}
