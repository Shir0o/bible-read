// TEMPORARY design-diff capture harness (test-only; no app code touched).
//
// Pumps the real app screens under the *actual* AppTheme light scheme with
// seeded fake data and captures screenshots, so they can be compared against
// the Claude Design prototype renders. Navigation is best-effort and wrapped so
// one unreachable screen never aborts the rest of the captures.
//
// Run:
//   flutter drive -d <device> \
//     --driver=test_driver/screenshot_driver.dart \
//     --target=integration_test/design_diff_capture_test.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/services/google_sign_in_factory.dart';
import 'package:bible_read/theme/app_theme.dart';
import 'package:bible_read/models/reading_plan.dart';
import '../test/helpers/fake_google_sign_in_platform.dart';
import 'helpers/screenshot_helper.dart';

void main() {
  initScreenshotBinding();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  String dk(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // Pump a fixed number of frames; never hangs on perpetual shimmer the way
  // pumpAndSettle can.
  Future<void> settle(WidgetTester tester, {int frames = 10}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  // Capture without re-converting the surface. The Android surface may be
  // converted to an image only once per session, so we convert a single time
  // (in the test body) and then just grab frames here.
  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, frames: 4);
    await screenshotBinding.takeScreenshot(name);
  }

  // Drag the primary scrollable. Negative dy reveals lower content; positive dy
  // scrolls back toward the top. Best-effort.
  Future<void> scrollBy(WidgetTester tester, double dy) async {
    try {
      final s = find.byType(Scrollable);
      if (s.evaluate().isEmpty) return;
      await tester.drag(s.first, Offset(0, dy));
      await settle(tester, frames: 6);
    } catch (_) {}
  }

  // Tap the first widget matching [finder] if present; ignore any failure so a
  // missing/unreachable control never aborts the run.
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

  testWidgets('capture design screens (light)', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final mockUser = MockUser(
      uid: 'u1',
      displayName: 'Tony',
      email: 'tony@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();

    final now = DateTime.now();

    // ---- User + summary (drives Journey streak/consistency) ----
    await firestore.collection('users').doc('u1').set({
      'displayName': 'Tony',
      'email': 'tony@example.com',
      'photoUrl': 'https://example.com/avatar.png',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final pastDates = <String>[
      for (var i = 0; i < 41; i++) dk(now.subtract(Duration(days: i * 2))),
    ];
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({
      'streak': 6,
      'totalReadDays': 41,
      'pastWeekReadDates': pastDates.take(5).toList(),
      'pastMonthReadDates': pastDates.take(18).toList(),
    });

    await firestore
        .collection('users')
        .doc('u1')
        .collection('settings')
        .doc('general')
        .set({'autoMarkPlanRead': true});

    // ---- Active personal plan (drives Home hero + Journey card) ----
    final plan = ReadingPlan(
      id: 'plan_1',
      title: 'The New Testament',
      description: 'Complete the New Testament.',
      durationDays: 260,
      tags: const [],
      schedule: [
        for (var d = 1; d <= 30; d++)
          ReadingPlanDay(day: d, readings: ['Romans $d']),
      ],
    );
    await firestore.collection('custom_plans').doc('plan_1').set({
      ...plan.toJson(),
      'userId': 'u1',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await firestore
        .collection('users')
        .doc('u1')
        .collection('plan_progress')
        .doc('plan_1')
        .set({
      'planId': 'plan_1',
      'userId': 'u1',
      'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 4))),
      'completedDays': [1, 2],
      'isArchived': false,
    });

    // ---- A reading group (drives Community) ----
    await firestore.collection('groups').doc('g1').set({
      'name': 'Tuesday Table',
      'ownerUid': 'owner1',
      'memberCount': 6,
      'createdAt': FieldValue.serverTimestamp(),
      'progress': 4,
      'planId': 'plan_1',
    });
    for (final m in ['u1', 'owner1', 'm2', 'm3', 'm4', 'm5']) {
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('members')
          .doc(m)
          .set({
        'uid': m, // groupsForUser() queries collectionGroup('members').where('uid', ...)
        'joinedAt': FieldValue.serverTimestamp(),
        'role': m == 'owner1' ? 'owner' : 'member',
        'displayName': m == 'u1' ? 'Tony' : 'Member ${m.toUpperCase()}',
      });
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('progress')
          .doc(m)
          .set({'count': m == 'u1' ? 2 : 4, 'lastRead': dk(now)});
    }

    // (Re)launch the app under a given scheme. Re-pumping with a new scheme is
    // how we capture light vs. dark of the same seeded state.
    Future<void> pumpApp(ColorScheme scheme) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.appTheme(scheme),
          home: MainPage(
            firestore: firestore,
            auth: auth,
            googleSignInProvider: createGoogleSignIn,
          ),
        ),
      );
      await settle(tester, frames: 14);
    }

    // ===================== LIGHT, not-yet-read =====================
    await pumpApp(AppTheme.designLightScheme);

    // Convert the surface to an image exactly once for this session. This is a
    // critical setup step for capture, so surface any failure (which would
    // otherwise produce blank/garbage screenshots) instead of swallowing it.
    try {
      await screenshotBinding.convertFlutterSurfaceToImage();
      await tester.pump();
    } catch (e, st) {
      debugPrint('convertFlutterSurfaceToImage failed: $e\n$st');
      rethrow;
    }

    // Tab switches first, from a clean top state (dragging before a tab tap was
    // making the bottom-nav hit-test miss).
    await shot(tester, '01_home_today');

    await tapIf(tester, find.text('Community'));
    await settle(tester, frames: 24);
    await shot(tester, '02_community');

    await tapIf(tester, find.text('Journey'));
    await settle(tester, frames: 24);
    await shot(tester, '03_journey');
    await scrollBy(tester, -440);
    await shot(tester, '03b_journey_schedule');

    await tapIf(tester, find.text('Home'));
    await settle(tester, frames: 8);
    await scrollBy(tester, -440);
    await shot(tester, '01b_home_scroll');
    await scrollBy(tester, 600); // back to top

    // ===================== DARK, not-yet-read =====================
    // Focus: button overlays + contrast against the dark background.
    await pumpApp(AppTheme.designDarkScheme);
    await shot(tester, '20_home_dark');
    await scrollBy(tester, -440);
    await shot(tester, '20b_home_dark_scroll');
    await scrollBy(tester, 600);

    await tapIf(tester, find.text('Community'));
    await settle(tester, frames: 24);
    await shot(tester, '22_community_dark');

    await tapIf(tester, find.text('Journey'));
    await settle(tester, frames: 24);
    await shot(tester, '23_journey_dark');

    await tapIf(tester, find.text('Home'));
    await settle(tester, frames: 8);

    // ===================== READ / "checked" state =====================
    // Mark the daily habit as read, then capture the resulting state.
    final marked = await tapIf(tester, find.text('I read today'));
    if (!marked) await tapIf(tester, find.text('I have read'));
    await settle(tester, frames: 12);
    await shot(tester, '21_home_dark_read');

    // Re-pump light to capture the same read/affirm state in light.
    await pumpApp(AppTheme.designLightScheme);
    await settle(tester, frames: 12);
    await shot(tester, '01c_home_read_light');
  });
}
