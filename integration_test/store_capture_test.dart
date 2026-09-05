// Store-listing capture harness (test-only; no app code touched).
//
// Pumps the real app screens under the real AppTheme with seeded fake data and
// captures the seven frames used in the App Store / Play listing. Every value
// on screen comes from the app's own widgets — nothing here draws UI.
//
// Run:
//   flutter drive -d <device> \
//     --driver=test_driver/screenshot_driver.dart \
//     --target=integration_test/store_capture_test.dart
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
import 'package:bible_read/pages/check_in_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/plan_detail_page.dart';
import 'package:bible_read/services/google_sign_in_factory.dart';
import 'package:bible_read/theme/app_theme.dart';
import 'package:bible_read/widgets/reflect_sheet.dart';
import '../test/helpers/fake_google_sign_in_platform.dart';
import 'helpers/screenshot_helper.dart';

/// The seeded reflection shown in the reflection sheet and the check-in payoff.
/// Matthew 14 is day 14's New Testament reading, so this is the real text for
/// the day the captures are pinned to.
const String kSeededReflection =
    'Fed five thousand from almost nothing. Kept thinking about the leftovers.';

/// Day 1–30 of "Bible in a Year (4 OT, 1 NT)", copied from
/// assets/plans/sample_plans.json so the captures show the real schedule.
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
  ['Exodus 11', 'Exodus 12', 'Exodus 13', 'Exodus 14', 'Matthew 16'],
  ['Exodus 15', 'Exodus 16', 'Exodus 17', 'Exodus 18', 'Matthew 17'],
  ['Exodus 19', 'Exodus 20', 'Exodus 21', 'Exodus 22', 'Matthew 18'],
  ['Exodus 23', 'Exodus 24', 'Exodus 25', 'Exodus 26', 'Matthew 19'],
  ['Exodus 27', 'Exodus 28', 'Exodus 29', 'Exodus 30', 'Matthew 20'],
  ['Exodus 31', 'Exodus 32', 'Exodus 33', 'Exodus 34', 'Matthew 21'],
  ['Exodus 35', 'Exodus 36', 'Exodus 37', 'Exodus 38', 'Matthew 22'],
  ['Exodus 39', 'Exodus 40', 'Leviticus 1', 'Leviticus 2', 'Matthew 23'],
  ['Leviticus 3', 'Leviticus 4', 'Leviticus 5', 'Leviticus 6', 'Matthew 24'],
  ['Leviticus 7', 'Leviticus 8', 'Leviticus 9', 'Leviticus 10', 'Matthew 25'],
  ['Leviticus 11', 'Leviticus 12', 'Leviticus 13', 'Leviticus 14', 'Matthew 26'],
  ['Leviticus 15', 'Leviticus 16', 'Leviticus 17', 'Leviticus 18', 'Matthew 27'],
  ['Leviticus 19', 'Leviticus 20', 'Leviticus 21', 'Leviticus 22', 'Matthew 28'],
  ['Leviticus 23', 'Leviticus 24', 'Leviticus 25', 'Leviticus 26', 'Mark 1'],
  ['Leviticus 27', 'Numbers 1', 'Numbers 2', 'Numbers 3', 'Mark 2'],
];

/// The group's own schedule runs a little behind the personal plan, so the two
/// cards on Home never show identical chapters.
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
  ['Luke 16'],
  ['Luke 17'],
  ['Luke 18'],
  ['Luke 19'],
  ['Luke 20'],
];

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

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, frames: 4);
    await screenshotBinding.takeScreenshot(name);
  }

  Future<void> scrollBy(WidgetTester tester, double dy) async {
    try {
      final s = find.byType(Scrollable);
      if (s.evaluate().isEmpty) {
        debugPrint('scrollBy: no scrollable found');
        return;
      }
      await tester.drag(s.first, Offset(0, dy));
      await settle(tester, frames: 6);
    } catch (e) {
      // Best-effort: a capture that cannot scroll is still worth taking, but
      // say why rather than failing silently.
      debugPrint('scrollBy($dy) failed: $e');
    }
  }

  Future<bool> tapIf(WidgetTester tester, Finder finder) async {
    try {
      if (finder.evaluate().isEmpty) {
        debugPrint('tapIf: no match for $finder');
        return false;
      }
      await tester.tap(finder.first);
      await settle(tester);
      return true;
    } catch (e) {
      // A missed tap means the next capture silently shows the previous
      // screen, which is how the duplicate-frame bugs hid — so log it.
      debugPrint('tapIf($finder) failed: $e');
      return false;
    }
  }

  testWidgets('capture store screens', (tester) async {
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

    // Day 14 is today: the plan started 13 days ago.
    final planStart = today.subtract(const Duration(days: 13));

    // ---- User + summary (drives Journey streak / consistency) ----
    await firestore.collection('users').doc('u1').set({
      'displayName': 'Sam',
      'email': 'sam@example.com',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Read on 11 of the last 13 days — matches the plan's two missed readings.
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

    // ---- Personal plan: day 14 due, two readings behind ----
    // Load the real 260-day plan out of the app's own asset, so Home reads
    // "11 of 260", not "11 of 30". Falls back to the embedded first 30 days if
    // the asset cannot be read.
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
    } catch (e) {
      debugPrint('plan asset unavailable, using embedded days: $e');
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
      tags: const ['Full Bible', 'Yearly', '4 OT + 1 NT'],
      schedule: schedule,
    );
    await firestore.collection('custom_plans').doc('plan_1').set({
      ...plan.toJson(),
      'userId': 'u1',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Days 11 and 12 are the misses -> "2 readings behind"; day 14 is today.
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

    // ---- Group "Morning Light": in step, nobody behind ----
    const members = {
      'u1': 'Sam',
      'owner1': 'Naomi',
      'm2': 'Elias',
      'm3': 'Ruth',
      'm4': 'Jonah',
      'm5': 'Miriam',
    };

    // Sam owns the group. This is not cosmetic: groupsForUser() merges three
    // snapshot streams and emits an EMPTY list first when the member query is
    // not the first to resolve. HomePage takes .first, so a non-owned group
    // silently never reaches "Today's reading". See the note in
    // design/store-assets/README.md.
    await firestore.collection('groups').doc('g1').set({
      'name': 'Morning Light',
      'ownerUid': 'u1',
      'memberCount': members.length,
      'createdAt': FieldValue.serverTimestamp(),
      'progress': 14,
      'planId': 'plan_1',
    });

    for (final entry in members.entries) {
      // Member avatars read names from the users collection, not the group's
      // member docs — without this they fall back to uid initials (O, M, M).
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
        'role': entry.key == 'u1' ? 'owner' : 'member',
        'displayName': entry.value,
      });
    }

    // The group schedule starts 13 days ago and runs a week past today.
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

    // Everyone is in step through today, so the group card reads "on track"
    // while the personal plan carries the behind row.
    for (var i = 0; i <= 13; i++) {
      final date = planStart.add(Duration(days: i));
      for (final uid in members.keys) {
        // Two members haven't logged today yet, so the presence row isn't a
        // suspiciously perfect 6 of 6.
        if (i == 13 && (uid == 'm4' || uid == 'm5')) continue;
        await firestore
            .collection('groups')
            .doc('g1')
            .collection('progress')
            .doc(dk(date))
            .collection('entries')
            .doc(uid)
            .set({
          'groupId': 'g1',
          'uid': uid,
          'dateId': dk(date),
          'count': 1,
          'done': true,
        });
      }
    }

    // ---- Friends + today's read log (drives the community glimpse) ----
    for (final entry in members.entries) {
      if (entry.key == 'u1') continue;
      await firestore
          .collection('users')
          .doc('u1')
          .collection('friends')
          .doc(entry.key)
          .set({'name': entry.value});
    }
    for (final entry in members.entries) {
      if (entry.key == 'm4' || entry.key == 'm5') continue;
      await firestore
          .collection('read_logs')
          .doc(dk(today))
          .collection('entries')
          .doc(entry.key)
          .set({'name': entry.value, 'uid': entry.key});
    }

    // ---- Reflection for today ----
    await firestore
        .collection('users')
        .doc('u1')
        .collection('reflections')
        .doc(dk(today))
        .set({'text': kSeededReflection, 'date': dk(today)});

    // A navigator key gives the reflection sheet a context that survives tab
    // switches — find.byType(MainPage) does not, if a tab throws.
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

      // Short pumps first: HomePage gives its group schedule/progress streams a
      // 3-second timeout, and settle()'s 250ms steps can burn that before the
      // fake Firestore streams deliver — which silently drops the group card
      // from Today's readings.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await settle(tester, frames: 16);

      // HomePage auto-opens the check-in page on launch when today is unmarked;
      // left alone it covers every screen we are trying to capture.
      final checkIn = find.byType(CheckInPage);
      if (checkIn.evaluate().isNotEmpty) {
        tester.widget<CheckInPage>(checkIn.first).onClose();
        await settle(tester, frames: 12);
      }
    }

    Future<void> pumpCheckIn({
      required bool readToday,
      required DateTime at,
      String? reflection,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.appTheme(AppTheme.designLightScheme),
          // A fresh key per pump forces a new State: `readToday` is read in
          // initState, so a reused State would keep showing the previous view.
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

    // The Android surface may be converted to an image only once per session.
    await pumpApp(AppTheme.designLightScheme);
    try {
      await screenshotBinding.convertFlutterSurfaceToImage();
      await tester.pump();
    } catch (e, st) {
      debugPrint('convertFlutterSurfaceToImage failed: $e\n$st');
      rethrow;
    }

    // ===================== 1. Check-in, the ask =====================
    await pumpCheckIn(readToday: false, at: today.add(const Duration(hours: 7)));
    await shot(tester, '10_checkin_dawn');

    await pumpCheckIn(
        readToday: false, at: today.add(const Duration(hours: 22)));
    await shot(tester, '11_checkin_night');

    // Day and dusk too, so the split has alternatives to choose from.
    await pumpCheckIn(
        readToday: false, at: today.add(const Duration(hours: 13)));
    await shot(tester, '12_checkin_day');

    await pumpCheckIn(
        readToday: false, at: today.add(const Duration(hours: 19)));
    await shot(tester, '13_checkin_dusk');

    // ===================== 7. Check-in, the payoff =====================
    await pumpCheckIn(
      readToday: true,
      at: today.add(const Duration(hours: 19)),
      reflection: kSeededReflection,
    );
    await shot(tester, '70_checkin_payoff_dusk');

    // ===================== 2. Home, personal behind =====================
    await pumpApp(AppTheme.designLightScheme);
    await shot(tester, '20_home_behind');
    await scrollBy(tester, -420);
    await shot(tester, '21_home_behind_scroll');
    await scrollBy(tester, 600);

    // ===================== 3. Journey / streak =====================
    await tapIf(tester, find.text('Journey'));
    await settle(tester, frames: 24);
    await shot(tester, '30_journey_streak');
    await scrollBy(tester, -420);
    await shot(tester, '31_journey_scroll');
    await scrollBy(tester, 600);

    // ===================== 4. Community =====================
    await tapIf(tester, find.text('Community'));
    await settle(tester, frames: 24);
    await shot(tester, '40_community');
    await scrollBy(tester, -420);
    await shot(tester, '41_community_scroll');

    // ===================== 6. Reflection sheet =====================
    await tapIf(tester, find.text('Home'));
    await settle(tester, frames: 12);
    // Non-fatal: a failure here must not cost us the plan-detail captures.
    try {
      final sheetContext = navigatorKey.currentContext;
      if (sheetContext != null) {
        openReflectSheet(
          sheetContext,
          initialText: kSeededReflection,
          prompt: reflectionPromptFor(today),
        );
        await settle(tester, frames: 16);
        await shot(tester, '60_reflect_sheet');
        await tapIf(tester, find.text('Skip for today'));
        await settle(tester, frames: 8);
      } else {
        debugPrint('reflect sheet skipped: no navigator context');
      }
    } catch (e, st) {
      debugPrint('reflect sheet capture failed: $e\n$st');
    }

    // ===================== 5. Plan detail, light + dark =====================
    Future<void> pumpPlanDetail(ColorScheme scheme) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.appTheme(scheme),
          home: PlanDetailPage(
            plan: plan,
            firestore: firestore,
            auth: auth,
            initialProgress: progress,
          ),
        ),
      );
      await settle(tester, frames: 20);
    }

    await pumpPlanDetail(AppTheme.designLightScheme);
    await shot(tester, '50_plan_detail_light');
    await scrollBy(tester, -420);
    await shot(tester, '51_plan_detail_light_scroll');

    await pumpPlanDetail(AppTheme.designDarkScheme);
    await shot(tester, '52_plan_detail_dark');
    await scrollBy(tester, -420);
    await shot(tester, '53_plan_detail_dark_scroll');
  });
}

/// Fire-and-forget wrapper: the sheet's future only completes when it closes,
/// which is after the capture.
void openReflectSheet(
  BuildContext context, {
  required String initialText,
  required String prompt,
}) {
  showReflectSheet(
    context,
    initialText: initialText,
    prompt: prompt,
    onSave: (_) async {},
  );
}
