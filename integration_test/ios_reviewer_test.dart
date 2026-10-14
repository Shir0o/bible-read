import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/models/reading_plan_progress.dart';
import 'package:bible_read/pages/check_in_page.dart';
import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/pages/login_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/settings_page.dart';
import 'package:bible_read/pages/welcome_page.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/theme/app_theme.dart';
import '../test/helpers/fake_google_sign_in_platform.dart';

const String kReviewerEmail = 'appreview@bibleread.app';
const String kReviewerPassword = 'ReviewPassword123!';
const String kReviewerName = 'App Reviewer';
const String kReviewerUid = 'reviewer_uid_123';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  String dk(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> settle(WidgetTester tester, {int frames = 8}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await settle(tester, frames: 4);
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot(name);
  }

  testWidgets('iOS App Store Reviewer complete evaluation journey', (tester) async {
    final firestore = FakeFirebaseFirestore();
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final planStart = today.subtract(const Duration(days: 7));

    // Seed mock reviewer user in Firestore
    await firestore.collection('users').doc(kReviewerUid).set({
      'displayName': kReviewerName,
      'email': kReviewerEmail,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final readDates = <String>[
      for (var i = 1; i <= 7; i++) dk(today.subtract(Duration(days: i))),
    ];

    await firestore
        .collection('users')
        .doc(kReviewerUid)
        .collection('summary')
        .doc('data')
        .set({
      'streak': 7,
      'totalReadDays': 21,
      'pastWeekReadDates': readDates,
      'pastMonthReadDates': readDates,
      'hasReadToday': true,
      'lastReadDate': dk(today),
    });

    // Seed a sample Reading Plan
    final plan = ReadingPlan(
      id: 'plan_reviewer',
      title: 'Bible in 90 Days',
      description: 'Daily scripture challenge designed for accountability and steady growth.',
      durationDays: 8,
      tags: const ['General', 'Review'],
      schedule: [
        for (var i = 1; i <= 8; i++)
          ReadingPlanDay(
            day: i,
            readings: ['Genesis $i', 'Matthew $i'],
          ),
      ],
    );
    await firestore.collection('custom_plans').doc(plan.id).set({
      ...plan.toJson(),
      'userId': kReviewerUid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final progress = UserPlanProgress(
      planId: plan.id,
      userId: kReviewerUid,
      startDate: planStart,
      lastReadDate: today,
      completedDays: [1, 2, 3, 4, 5, 6],
    );
    await firestore
        .collection('users')
        .doc(kReviewerUid)
        .collection('plan_progress')
        .doc(plan.id)
        .set(progress.toFirestore());

    // Seed Community Group
    await firestore.collection('groups').doc('group_review').set({
      'name': 'Grace Reading Circle',
      'ownerUid': kReviewerUid,
      'memberCount': 4,
      'createdAt': FieldValue.serverTimestamp(),
      'progress': 65,
      'planId': plan.id,
    });
    await firestore
        .collection('groups')
        .doc('group_review')
        .collection('members')
        .doc(kReviewerUid)
        .set({
      'joinedAt': FieldValue.serverTimestamp(),
      'role': 'owner',
    });

    // Auth starts unauthenticated so reviewer sees WelcomePage
    final auth = MockFirebaseAuth(signedIn: false);
    await auth.createUserWithEmailAndPassword(
      email: kReviewerEmail,
      password: kReviewerPassword,
    );
    await auth.signOut();

    // Launch App
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.appTheme(AppTheme.seededColorScheme(Brightness.light)),
        home: MainPage(
          auth: auth,
          firestore: firestore,
          googleSignInProvider: () => GoogleSignInPlatform.instance as dynamic,
          vibrationService: const VibrationService(),
        ),
      ),
    );
    await settle(tester, frames: 10);

    // 1. Welcome Page
    expect(find.byType(WelcomePage), findsOneWidget);
    await capture(tester, 'ios_01_welcome');

    // 2. Navigate to Login Page
    final loginButton = find.text('I already have an account');
    expect(loginButton, findsOneWidget);
    await tester.tap(loginButton);
    await settle(tester, frames: 8);

    expect(find.byType(LoginPage), findsOneWidget);
    await capture(tester, 'ios_02_login_blank');

    // 3. Enter Reviewer Credentials
    final emailField = find.byKey(const Key('loginEmailField'));
    final passwordField = find.byKey(const Key('loginPasswordField'));
    expect(emailField, findsOneWidget);
    expect(passwordField, findsOneWidget);

    await tester.enterText(emailField, kReviewerEmail);
    await tester.enterText(passwordField, kReviewerPassword);
    await settle(tester, frames: 4);
    await capture(tester, 'ios_03_login_filled');

    // 4. Submit Login
    final submitButton = find.widgetWithText(ElevatedButton, 'Log in');
    expect(submitButton, findsOneWidget);
    await tester.ensureVisible(submitButton);
    await settle(tester, frames: 4);
    await tester.tap(submitButton);
    await tester.pump();
    await tester.pumpAndSettle();
    await settle(tester, frames: 10);

    // If CheckInPage modal appears, capture and dismiss
    final checkInPrompt = find.byType(CheckInPage);
    if (checkInPrompt.evaluate().isNotEmpty) {
      await capture(tester, 'ios_04_checkin_modal');
      tester.widget<CheckInPage>(checkInPrompt).onClose();
      await tester.pumpAndSettle();
      await settle(tester, frames: 6);
    }

    // 5. Verify Home Page (Today Tab)
    expect(find.byType(HomePage), findsOneWidget);
    await capture(tester, 'ios_05_today_home');

    // 6. Navigate to Circle Tab
    final circleTab = find.text('Circle');
    expect(circleTab, findsOneWidget);
    await tester.tap(circleTab, warnIfMissed: false);
    await settle(tester, frames: 8);
    await capture(tester, 'ios_06_circle_community');

    // 7. Navigate to Path Tab
    final pathTab = find.text('Path');
    expect(pathTab, findsOneWidget);
    await tester.tap(pathTab, warnIfMissed: false);
    await settle(tester, frames: 8);
    await capture(tester, 'ios_07_path_journey');

    // 8. Open Settings via Menu
    final todayTab = find.text('Today');
    await tester.tap(todayTab, warnIfMissed: false);
    await settle(tester, frames: 6);

    // Open menu via avatar
    final openMenuButton = find.bySemanticsLabel('Open menu');
    expect(openMenuButton, findsOneWidget);
    await tester.tap(openMenuButton);
    await settle(tester, frames: 8);

    final settingsItem = find.text('Settings');
    expect(settingsItem, findsOneWidget);
    await tester.tap(settingsItem);
    await settle(tester, frames: 8);

    expect(find.byType(SettingsPage), findsOneWidget);

    // Apple Guideline 5.1.1(v) Check: Delete Account option must be visible
    expect(find.text('Delete Account'), findsOneWidget);

    // Support check: Report a bug & Request a feature
    expect(find.text('Report a bug'), findsOneWidget);
    expect(find.text('Request a feature'), findsOneWidget);

    await capture(tester, 'ios_08_settings_compliance');
  });
}
