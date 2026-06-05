// Tests for the Home redesign (#722/#723): the daily habit is the hero, the
// personal plan's reading appears as a separate, secondary "Today's reading"
// card, and with no active plan nothing prescriptive is shown.
//
// These build MaterialApp with NoSplash to avoid the InkSparkle fragment-shader
// asset that the headless test environment can't decode, so plan-card taps are
// exercisable here.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/services/bible_progress_service.dart';
import 'package:bible_read/services/reading_plan_service.dart';
import 'package:bible_read/services/user_preferences_service.dart';
import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/models/reading_plan_progress.dart';
import '../helpers/mock_lottie_http_client.dart';

class _StubBibleProgressService extends BibleProgressService {
  _StubBibleProgressService() : super(firestore: FakeFirebaseFirestore());
}

Widget _host(Widget home) => MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        splashFactory: NoSplash.splashFactory,
      ),
      home: home,
    );

Future<void> _seedPlan(
  FakeFirebaseFirestore firestore,
  ReadingPlanService planService, {
  required DateTime now,
}) async {
  const plan = ReadingPlan(
    id: 'p1',
    title: 'Test Plan',
    description: 'Desc',
    durationDays: 30,
    tags: [],
    schedule: [
      ReadingPlanDay(day: 1, readings: ['Genesis 1']),
      ReadingPlanDay(day: 2, readings: ['Genesis 2']),
    ],
  );
  await firestore.collection('custom_plans').doc('p1').set({
    ...plan.toJson(),
    'userId': 'u1',
  });
  await planService.startPlan('u1', 'p1', startDate: now);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    setupLottieHttpOverrides();
  });
  tearDownAll(resetHttpOverrides);

  testWidgets(
    'no active plan: habit hero shown, no "Today’s reading" card (#723)',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);

      await tester.pumpWidget(
        _host(HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: const VibrationService(),
          bibleProgressService: _StubBibleProgressService(),
          dateProvider: DateTime.now,
        )),
      );
      await tester.pumpAndSettle();

      // Habit hero present and dominant.
      expect(find.byKey(const ValueKey('habit_todo')), findsOneWidget);
      expect(find.text('Read whatever you’re drawn to.'), findsOneWidget);
      expect(find.text('I read today'), findsOneWidget);

      // Nothing prescriptive: no plan reading card.
      expect(find.text('Today’s reading'), findsNothing);
      expect(find.text('Mark as read'), findsNothing);
    },
  );

  testWidgets(
    'active plan: habit hero AND a separate "Today’s reading" card (#722)',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
      final planService = ReadingPlanService(firestore: firestore);
      await _seedPlan(firestore, planService, now: DateTime.now());

      await tester.pumpWidget(
        _host(HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: const VibrationService(),
          bibleProgressService: _StubBibleProgressService(),
          readingPlanService: planService,
          dateProvider: DateTime.now,
        )),
      );
      await tester.pumpAndSettle();

      // Habit hero remains the hero, now with the plan-aware prompt.
      expect(find.text('Did you spend time in the Word?'), findsOneWidget);
      expect(find.text('I read today'), findsOneWidget);

      // Plus a distinct plan reading card.
      expect(find.text('Today’s reading'), findsOneWidget);
      expect(find.text('Genesis 1'), findsOneWidget);
      expect(find.text('Mark as read'), findsOneWidget);
    },
  );

  testWidgets(
    'plan card mark advances the plan and asks the coupling question once',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
      final planService = ReadingPlanService(firestore: firestore);
      await _seedPlan(firestore, planService, now: DateTime.now());

      await tester.pumpWidget(
        _host(HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: const VibrationService(),
          bibleProgressService: _StubBibleProgressService(),
          readingPlanService: planService,
          userPreferencesService: UserPreferencesService(firestore: firestore),
          dateProvider: DateTime.now,
        )),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark as read'));
      await tester.pumpAndSettle();

      // First completion shows the one-time coupling prompt (SyncSheet).
      expect(find.text('Keep them separate'), findsOneWidget);
      await tester.tap(find.text('Keep them separate'));
      await tester.pumpAndSettle();

      // The plan day was recorded.
      final progressDoc = await firestore
          .collection('users')
          .doc('u1')
          .collection('plan_progress')
          .doc('p1')
          .get();
      final progress = UserPlanProgress.fromFirestore(progressDoc);
      expect(progress.completedDays, contains(1));

      // The card now reflects the read state.
      expect(find.text('Read'), findsOneWidget);
    },
  );
}
