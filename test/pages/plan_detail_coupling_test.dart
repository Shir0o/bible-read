import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/models/reading_plan_progress.dart';
import 'package:bible_read/models/user_preferences.dart';
import 'package:bible_read/pages/plan_detail_page.dart';
import 'package:bible_read/services/reading_plan_service.dart';
import 'package:bible_read/services/user_preferences_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubVibrationService extends VibrationService {
  const _StubVibrationService();
  @override
  Future<void> lightImpact() async {}
  @override
  Future<void> mediumImpact() async {}
}

/// A single-day plan that starts today, so its only reading lands in the
/// "Today" section and can be tapped to finish.
const _plan = ReadingPlan(
  id: 'p1',
  title: 'Plan 1',
  description: 'Desc',
  durationDays: 1,
  tags: [],
  schedule: [
    ReadingPlanDay(day: 1, readings: ['Gen 1']),
  ],
);

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late ReadingPlanService planService;
  late UserPreferencesService prefsService;
  late UserPlanProgress startedProgress;

  String todayKey() {
    final t = DateTime.now();
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  Future<bool> habitRecordedToday() async {
    final doc = await firestore
        .collection('users')
        .doc('u1')
        .collection('reading')
        .doc(todayKey())
        .get();
    return doc.exists && doc.data()?['read'] == true;
  }

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    planService = ReadingPlanService(firestore: firestore);
    prefsService = UserPreferencesService(firestore: firestore);

    await firestore.collection('custom_plans').doc('p1').set({
      ..._plan.toJson(),
      'userId': 'u1',
    });
    await planService.startPlan('u1', 'p1', startDate: DateTime.now());
    startedProgress = (await planService.getPlanProgress('u1', 'p1').first)!;
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        // Avoid the Material 3 sparkle ink, whose shader asset fails to load
        // in the test environment when the reading's InkWell is tapped.
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: PlanDetailPage(
          plan: _plan,
          firestore: firestore,
          auth: auth,
          initialProgress: startedProgress,
          vibrationService: const _StubVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));
  }

  // Taps today's reading. `_toggleDay` awaits Firestore-backed futures that the
  // fake-async pump loop won't drain, so the tap runs in `runAsync`; the
  // following `pumpAndSettle` then renders any resulting sheet/UI.
  Future<void> tapReading(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('Gen 1'));
      await Future.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('first finish under "ask" shows the SyncSheet only once', (
    tester,
  ) async {
    await pumpPage(tester);

    // Finish today's reading -> the one-time prompt appears.
    await tapReading(tester);
    expect(find.text("You finished today's reading"), findsOneWidget);

    // Choose to link them.
    await tester.runAsync(() async {
      await tester.tap(find.text('Yes, count it as showing up'));
      await Future.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    final prefs = await prefsService.fetchPreferences('u1');
    expect(prefs.syncPromptAnswered, isTrue);
    expect(prefs.autoMarkPlanRead, isTrue);
    expect(await habitRecordedToday(), isTrue);

    // Un-mark then re-finish: the prompt must not reappear.
    await tapReading(tester);
    await tapReading(tester);
    expect(find.text("You finished today's reading"), findsNothing);
  });

  testWidgets('linked: finishing a reading records the habit, no prompt', (
    tester,
  ) async {
    await prefsService.updatePreferences(
      'u1',
      const UserPreferences(autoMarkPlanRead: true, syncPromptAnswered: true),
    );

    await pumpPage(tester);
    await tapReading(tester);

    expect(find.text("You finished today's reading"), findsNothing);
    expect(await habitRecordedToday(), isTrue);
  });

  testWidgets('separate: finishing a reading does not record the habit', (
    tester,
  ) async {
    await prefsService.updatePreferences(
      'u1',
      const UserPreferences(autoMarkPlanRead: false, syncPromptAnswered: true),
    );

    await pumpPage(tester);
    await tapReading(tester);

    expect(find.text("You finished today's reading"), findsNothing);
    expect(await habitRecordedToday(), isFalse);
  });
}
