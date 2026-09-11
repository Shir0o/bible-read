// Pre-submission end-to-end feature assessment and visual audit harness.
//
// Exercises the real application screens across Light and Dark themes with
// deterministic seeded data and captures full-resolution screenshots for
// the pre-submission compliance audit report (docs/pre_submission_assessment.md).
//
// Run on physical device (Pixel 10 Pro):
//   flutter drive -d 57281FDCH006AY --no-enable-impeller \
//     --driver=test_driver/screenshot_driver.dart \
//     --target=integration_test/feature_assessment_test.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/models/reading_plan_progress.dart';
import 'package:bible_read/pages/auth_selection_page.dart';
import 'package:bible_read/pages/bible_progress_page.dart';
import 'package:bible_read/pages/challenges_page.dart';
import 'package:bible_read/pages/check_in_page.dart';
import 'package:bible_read/pages/login_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/notification_settings_page.dart';
import 'package:bible_read/pages/plan_detail_page.dart';
import 'package:bible_read/pages/read_throughs_page.dart';
import 'package:bible_read/pages/settings_page.dart';
import 'package:bible_read/pages/signup_page.dart';
import 'package:bible_read/pages/welcome_page.dart';
import 'package:bible_read/services/google_sign_in_factory.dart';
import 'package:bible_read/services/notification_preferences_service.dart';
import 'package:bible_read/theme/app_theme.dart';
import 'package:bible_read/widgets/reflect_sheet.dart';
import 'package:bible_read/services/vibration_service.dart';
import '../test/helpers/fake_google_sign_in_platform.dart';
import 'helpers/screenshot_helper.dart';

const String kSeededReflection =
    'Fed five thousand from almost nothing. Kept thinking about the leftovers.';

const List<List<String>> kPlanReadings = [
  ['Genesis 1', 'Genesis 2', 'Genesis 3', 'Genesis 4', 'Matthew 1'],
  ['Genesis 5', 'Genesis 6', 'Genesis 7', 'Genesis 8', 'Matthew 2'],
  ['Genesis 9', 'Genesis 10', 'Genesis 11', 'Genesis 12', 'Matthew 3'],
  ['Genesis 13', 'Genesis 14', 'Genesis 15', 'Genesis 16', 'Matthew 4'],
  ['Genesis 17', 'Genesis 18', 'Genesis 19', 'Genesis 20', 'Matthew 5'],
  ['Genesis 21', 'Genesis 22', 'Genesis 23', 'Genesis 24', 'Matthew 6'],
  ['Genesis 25', 'Genesis 26', 'Genesis 27', 'Genesis 28', 'Matthew 7'],
  ['Genesis 29', 'Genesis 30', 'Genesis 31', 'Genesis 32', 'Matthew 8'],
  ['Genesis 33', 'Genesis 34', 'Genesis 35', 'Genesis 36', 'Matthew 9'],
  ['Genesis 37', 'Genesis 38', 'Genesis 39', 'Genesis 40', 'Matthew 10'],
  ['Genesis 41', 'Genesis 42', 'Genesis 43', 'Genesis 44', 'Matthew 11'],
  ['Genesis 45', 'Genesis 46', 'Genesis 47', 'Genesis 48', 'Matthew 12'],
  ['Genesis 49', 'Genesis 50', 'Exodus 1', 'Exodus 2', 'Matthew 13'],
  ['Exodus 3', 'Exodus 4', 'Exodus 5', 'Exodus 6', 'Matthew 14'],
  ['Exodus 7', 'Exodus 8', 'Exodus 9', 'Exodus 10', 'Matthew 15'],
];

const List<List<String>> kGroupReadings = [
  ['Luke 1'],
  ['Luke 2'],
  ['Luke 3'],
  ['Luke 4'],
  ['Luke 5'],
  ['Luke 6'],
  ['Luke 7'],
  ['Luke 8'],
  ['Luke 9'],
  ['Luke 10'],
  ['Luke 11'],
  ['Luke 12'],
  ['Luke 13'],
  ['Luke 14'],
  ['Luke 15'],
];

void main() {
  initScreenshotBinding();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  String dk(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> settle(WidgetTester tester, {int frames = 10}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, frames: 4);
    await screenshotBinding.takeScreenshot(name);
  }

  Future<void> scrollBy(WidgetTester tester, double dy) async {
    try {
      final s = find.byType(Scrollable);
      if (s.evaluate().isEmpty) return;
      await tester.drag(s.first, Offset(0, dy));
      await settle(tester, frames: 6);
    } catch (_) {}
  }

  Future<bool> tapIf(WidgetTester tester, Finder finder) async {
    try {
      if (finder.evaluate().isEmpty) return false;
      await tester.tap(finder.first);
      await settle(tester);
      return true;
    } catch (_) {
      return false;
    }
  }

  testWidgets('assess all features and capture full visual audit gallery', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final mockUser = MockUser(
      uid: 'u1',
      displayName: 'Sam',
      email: 'sam@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final planStart = today.subtract(const Duration(days: 13));

    // Seed User
    await firestore.collection('users').doc('u1').set({
      'displayName': 'Sam',
      'email': 'sam@example.com',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final readDates = <String>[
      for (var i = 1; i <= 13; i++)
        if (i != 2 && i != 3) dk(today.subtract(Duration(days: i))),
    ];
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({
      'streak': 11,
      'totalReadDays': 41,
      'pastWeekReadDates': readDates.take(5).toList(),
      'pastMonthReadDates': readDates,
    });

    await firestore
        .collection('users')
        .doc('u1')
        .collection('settings')
        .doc('general')
        .set({'autoMarkPlanRead': true});

    // Seed Plan
    List<ReadingPlanDay> schedule;
    try {
      final raw = await rootBundle.loadString('assets/plans/sample_plans.json');
      final planJson = (jsonDecode(raw) as List).first as Map<String, dynamic>;
      schedule = [
        for (final day in planJson['schedule'] as List)
          ReadingPlanDay(
            day: (day as Map)['day'] as int,
            readings: (day['readings'] as List).cast<String>(),
          ),
      ];
    } catch (_) {
      schedule = [
        for (var d = 1; d <= kPlanReadings.length; d++)
          ReadingPlanDay(day: d, readings: kPlanReadings[d - 1]),
      ];
    }

    final plan = ReadingPlan(
      id: 'plan_1',
      title: 'Bible in a Year (4 OT, 1 NT)',
      description:
          'Read through the entire Bible with 4 Old Testament chapters and 1 New Testament chapter daily.',
      durationDays: 260,
      tags: const ['Full Bible', 'Yearly'],
      schedule: schedule,
    );
    await firestore.collection('custom_plans').doc('plan_1').set({
      ...plan.toJson(),
      'userId': 'u1',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final completedDays = [for (var d = 1; d <= 13; d++) d]
      ..removeWhere((d) => d == 11 || d == 12);
    final progress = UserPlanProgress(
      planId: 'plan_1',
      userId: 'u1',
      startDate: planStart,
      completedDays: completedDays,
      lastReadDate: today.subtract(const Duration(days: 1)),
    );
    await firestore
        .collection('users')
        .doc('u1')
        .collection('plan_progress')
        .doc('plan_1')
        .set({
      'planId': 'plan_1',
      'userId': 'u1',
      'startDate': Timestamp.fromDate(planStart),
      'completedDays': completedDays,
      'isArchived': false,
    });

    // Seed Group
    const members = {
      'u1': 'Sam',
      'owner1': 'Naomi',
      'm2': 'Elias',
      'm3': 'Ruth',
      'm4': 'Jonah',
    };

    await firestore.collection('groups').doc('g1').set({
      'name': 'Morning Light',
      'ownerUid': 'owner1',
      'memberCount': members.length,
      'createdAt': FieldValue.serverTimestamp(),
      'progress': 14,
      'planId': 'plan_1',
    });

    for (final entry in members.entries) {
      await firestore.collection('users').doc(entry.key).set({
        'displayName': entry.value,
        'email': '${entry.value.toLowerCase()}@example.com',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await firestore
          .collection('groups')
          .doc('g1')
          .collection('members')
          .doc(entry.key)
          .set({
        'uid': entry.key,
        'joinedAt': FieldValue.serverTimestamp(),
        'role': entry.key == 'owner1' ? 'owner' : 'member',
        'displayName': entry.value,
      });
    }

    for (var i = 0; i < kGroupReadings.length; i++) {
      final date = planStart.add(Duration(days: i));
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('schedule')
          .doc(dk(date))
          .set({
        'date': Timestamp.fromDate(DateTime.utc(date.year, date.month, date.day)),
        'chapters': kGroupReadings[i],
      });
    }

    // Seed Reflection
    await firestore
        .collection('users')
        .doc('u1')
        .collection('reflections')
        .doc(dk(today))
        .set({'text': kSeededReflection, 'date': dk(today)});

    final navigatorKey = GlobalKey<NavigatorState>();

    Future<void> pumpApp(ColorScheme scheme) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: AppTheme.appTheme(scheme),
          home: MainPage(
            firestore: firestore,
            auth: auth,
            googleSignInProvider: createGoogleSignIn,
          ),
        ),
      );
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await settle(tester, frames: 16);

      final checkIn = find.byType(CheckInPage);
      if (checkIn.evaluate().isNotEmpty) {
        tester.widget<CheckInPage>(checkIn.first).onClose();
        await settle(tester, frames: 12);
      }
    }

    // Convert surface once for the session
    await pumpApp(AppTheme.designLightScheme);
    await screenshotBinding.convertFlutterSurfaceToImage();
    await tester.pump();

    // ==================== 1. AUTH & ONBOARDING ====================
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.appTheme(AppTheme.designLightScheme),
        home: WelcomePage(
          onGetStarted: () {},
          onLogin: () {},
        ),
      ),
    );
    await settle(tester, frames: 10);
    await shot(tester, '01_auth_welcome');

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.appTheme(AppTheme.designLightScheme),
        home: AuthSelectionPage(
          auth: auth,
          firestore: firestore,
        ),
      ),
    );
    await settle(tester, frames: 10);
    await shot(tester, '02_auth_selection');

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.appTheme(AppTheme.designLightScheme),
        home: LoginPage(auth: auth, firestore: firestore),
      ),
    );
    await settle(tester, frames: 10);
    await shot(tester, '03_auth_login');

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.appTheme(AppTheme.designLightScheme),
        home: SignupPage(auth: auth, firestore: firestore),
      ),
    );
    await settle(tester, frames: 10);
    await shot(tester, '04_auth_signup');

    // ==================== 2. DAILY CHECK-IN PHASES ====================
    Future<void> pumpCheckIn({
      required bool readToday,
      required DateTime at,
      String? reflection,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.appTheme(AppTheme.designLightScheme),
          home: CheckInPage(
            key: ValueKey('checkin-$readToday-${at.hour}'),
            readToday: readToday,
            seasonDays: 41,
            reflection: reflection,
            onConfirmRead: () async {},
            onReflect: () {},
            onClose: () {},
            dateProvider: () => at,
            enableDriftAnimation: false,
          ),
        ),
      );
      await settle(tester, frames: 16);
    }

    await pumpCheckIn(readToday: false, at: today.add(const Duration(hours: 7)));
    await shot(tester, '10_checkin_dawn');

    await pumpCheckIn(readToday: false, at: today.add(const Duration(hours: 13)));
    await shot(tester, '11_checkin_day');

    await pumpCheckIn(readToday: false, at: today.add(const Duration(hours: 19)));
    await shot(tester, '12_checkin_dusk');

    await pumpCheckIn(readToday: false, at: today.add(const Duration(hours: 22)));
    await shot(tester, '13_checkin_night');

    await pumpCheckIn(
      readToday: true,
      at: today.add(const Duration(hours: 19)),
      reflection: kSeededReflection,
    );
    await shot(tester, '14_checkin_payoff');

    // ==================== 3. TODAY TAB ====================
    await pumpApp(AppTheme.designLightScheme);
    await shot(tester, '20_today_behind');
    await scrollBy(tester, -450);
    await shot(tester, '21_today_behind_scrolled');
    await scrollBy(tester, 600);

    // Reflection Sheet
    try {
      final sheetCtx = navigatorKey.currentContext;
      if (sheetCtx != null) {
        showReflectSheet(
          sheetCtx,
          initialText: kSeededReflection,
          prompt: 'What stood out to you in Exodus 3-6 today?',
          onSave: (_, __) async {},
        );
        await settle(tester, frames: 16);
        await shot(tester, '22_today_reflection_sheet');
        await tapIf(tester, find.text('Skip for today'));
        await settle(tester, frames: 8);
      }
    } catch (_) {}

    // ==================== 4. CIRCLE TAB ====================
    await tapIf(tester, find.text('Circle'));
    await settle(tester, frames: 24);
    await shot(tester, '30_circle_hub');
    await scrollBy(tester, -450);
    await shot(tester, '31_circle_scrolled');
    await scrollBy(tester, 600);

    // ==================== 5. PATH TAB ====================
    await tapIf(tester, find.text('Path'));
    await settle(tester, frames: 24);
    await shot(tester, '40_path_hub');
    await scrollBy(tester, -450);
    await shot(tester, '41_path_scrolled');
    await scrollBy(tester, 600);

    // Plan Detail Page
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.appTheme(AppTheme.designLightScheme),
        home: PlanDetailPage(
          plan: plan,
          firestore: firestore,
          auth: auth,
          initialProgress: progress,
        ),
      ),
    );
    await settle(tester, frames: 20);
    await shot(tester, '42_path_plan_detail');
    await scrollBy(tester, -500);
    await shot(tester, '43_path_plan_schedule');

    // ==================== 6. PROGRESS & BADGES ====================
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.appTheme(AppTheme.designLightScheme),
        home: BibleProgressPage(firestore: firestore, auth: auth),
      ),
    );
    await settle(tester, frames: 20);
    await shot(tester, '50_progress_bible_books');

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.appTheme(AppTheme.designLightScheme),
        home: ReadThroughsPage(firestore: firestore, auth: auth),
      ),
    );
    await settle(tester, frames: 20);
    await shot(tester, '51_progress_read_throughs');

    // ==================== 7. SEASONAL CHALLENGES ====================
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.appTheme(AppTheme.designLightScheme),
        home: ChallengesPage(
          firestore: firestore,
          auth: auth,
          vibrationService: const VibrationService(),
        ),
      ),
    );
    await settle(tester, frames: 20);
    await shot(tester, '60_seasonal_challenges');

    // ==================== 8. SETTINGS & COMPLIANCE ====================
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.appTheme(AppTheme.designLightScheme),
        home: SettingsPage(
          auth: auth,
          firestore: firestore,
          googleSignInProvider: createGoogleSignIn,
        ),
      ),
    );
    await settle(tester, frames: 20);
    await shot(tester, '70_settings_hub');
    await scrollBy(tester, -500);
    await shot(tester, '71_settings_account_section');

    // Delete Account Dialog
    final deleteTile = find.text('Delete Account');
    if (deleteTile.evaluate().isNotEmpty) {
      await tester.ensureVisible(deleteTile);
      await tester.pumpAndSettle();
      await tester.tap(deleteTile);
      await settle(tester, frames: 12);
      await shot(tester, '72_settings_delete_account_dialog');
      await tapIf(tester, find.text('Cancel'));
      await settle(tester, frames: 8);
    }

    // Notification Settings
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.appTheme(AppTheme.designLightScheme),
        home: NotificationSettingsPage(
          auth: auth,
          service: NotificationPreferencesService(firestore: firestore),
        ),
      ),
    );
    await settle(tester, frames: 20);
    await shot(tester, '73_settings_notifications');

    // ==================== 9. DARK THEME KEY SURFACES ====================
    await pumpApp(AppTheme.designDarkScheme);
    await shot(tester, '80_dark_today');

    await tapIf(tester, find.text('Circle'));
    await settle(tester, frames: 20);
    await shot(tester, '81_dark_circle');

    await tapIf(tester, find.text('Path'));
    await settle(tester, frames: 20);
    await shot(tester, '82_dark_path');

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.appTheme(AppTheme.designDarkScheme),
        home: SettingsPage(
          auth: auth,
          firestore: firestore,
          googleSignInProvider: createGoogleSignIn,
        ),
      ),
    );
    await settle(tester, frames: 20);
    await scrollBy(tester, -500);
    await shot(tester, '83_dark_settings_account');
  });
}
