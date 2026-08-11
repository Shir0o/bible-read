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
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/reading_plan_service.dart';
import 'package:bible_read/services/user_preferences_service.dart';
import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/models/reading_plan_progress.dart';
import 'package:bible_read/models/user_preferences.dart';
import '../helpers/mock_lottie_http_client.dart';

class _StubBibleProgressService extends BibleProgressService {
  _StubBibleProgressService() : super(firestore: FakeFirebaseFirestore());
}

Widget _host(Widget home) => MaterialApp(
      theme:
          ThemeData(useMaterial3: true, splashFactory: NoSplash.splashFactory),
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
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1'),
        signedIn: true,
      );

      await tester.pumpWidget(
        _host(
          HomePage(
            firestore: firestore,
            auth: auth,
            vibrationService: const VibrationService(),
            bibleProgressService: _StubBibleProgressService(),
            dateProvider: DateTime.now,
            enableDriftAnimation: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Auto-opens CheckInPage.
      expect(find.text('Did you read today?'), findsOneWidget);
      expect(find.text('I READ'), findsOneWidget);

      // Dismiss CheckInPage back to Home
      await tester.tap(find.bySemanticsLabel('Dismiss check-in'));
      await tester.pumpAndSettle();

      // Nothing prescriptive: no plan reading card.
      expect(find.text('Today’s reading'), findsNothing);
      expect(find.text('Mark as read'), findsNothing);
    },
  );

  testWidgets(
    'active plan: habit check-in AND a separate "Today’s reading" card (#722)',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1'),
        signedIn: true,
      );
      final planService = ReadingPlanService(firestore: firestore);
      await _seedPlan(firestore, planService, now: DateTime.now());

      await tester.pumpWidget(
        _host(
          HomePage(
            firestore: firestore,
            auth: auth,
            vibrationService: const VibrationService(),
            bibleProgressService: _StubBibleProgressService(),
            readingPlanService: planService,
            dateProvider: DateTime.now,
            enableDriftAnimation: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Auto-opens CheckInPage. Dismiss to view Home page.
      expect(find.text('Did you read today?'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Dismiss check-in'));
      await tester.pumpAndSettle();

      // Plus a distinct plan reading card.
      expect(find.text('Today’s reading'), findsOneWidget);
      expect(find.text('Genesis 1'), findsOneWidget);
      expect(find.text('Mark as read'), findsOneWidget);
    },
  );

  testWidgets('read state + active plan fits a phone viewport (no overflow)', (
    tester,
  ) async {
    // Default 800x600 test surface — the size at which CI caught a 20px
    // overflow before the SliverToBoxAdapter fix.
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    final planService = ReadingPlanService(firestore: firestore);
    await _seedPlan(firestore, planService, now: DateTime.now());

    // Already showed up today.
    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    await firestore
        .collection('users')
        .doc('u1')
        .collection('reading')
        .doc(dateKey)
        .set({'read': true});
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({
      'streak': 5,
      'totalReadDays': 5,
      'pastWeekReadDates': [dateKey],
    });

    await tester.pumpWidget(
      _host(
        HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: const VibrationService(),
          bibleProgressService: _StubBibleProgressService(),
          readingPlanService: planService,
          dateProvider: DateTime.now,
          enableDriftAnimation: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Marked SunMark header button, plan reading card and the consistency glimpse all
    // coexist…
    expect(
      find.bySemanticsLabel('You read today — open check-in'),
      findsOneWidget,
    );
    expect(find.text('Today’s reading'), findsOneWidget);
    expect(find.text('Here 5 days this season'), findsOneWidget);
    // …without a layout overflow.
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'plan card mark advances the plan and asks the coupling question once',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1'),
        signedIn: true,
      );
      final planService = ReadingPlanService(firestore: firestore);
      await _seedPlan(firestore, planService, now: DateTime.now());

      await tester.pumpWidget(
        _host(
          HomePage(
            firestore: firestore,
            auth: auth,
            vibrationService: const VibrationService(),
            bibleProgressService: _StubBibleProgressService(),
            readingPlanService: planService,
            userPreferencesService: UserPreferencesService(
              firestore: firestore,
            ),
            dateProvider: DateTime.now,
            enableDriftAnimation: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (find.bySemanticsLabel('Dismiss check-in').evaluate().isNotEmpty) {
        await tester.tap(find.bySemanticsLabel('Dismiss check-in'));
        await tester.pumpAndSettle();
      }

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

      // The habit today was recorded in Firestore.
      final today = DateTime.now();
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final habitDoc = await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc(dateKey)
          .get();
      expect(habitDoc.exists, isFalse);

      // The card now reflects the read state, non-interactively (design
      // parity: no standing undo-by-retap — only the just-shown snackbar's
      // Undo can reverse this).
      expect(find.text('Read · Genesis 1'), findsOneWidget);
    },
  );

  testWidgets(
    'plan card mark with coupling already linked marks the daily habit too',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1'),
        signedIn: true,
      );
      final planService = ReadingPlanService(firestore: firestore);
      await _seedPlan(firestore, planService, now: DateTime.now());

      final prefsService = UserPreferencesService(firestore: firestore);
      await prefsService.updatePreferences(
        'u1',
        const UserPreferences(autoMarkPlanRead: true, syncPromptAnswered: true),
      );

      await tester.pumpWidget(
        _host(
          HomePage(
            firestore: firestore,
            auth: auth,
            vibrationService: const VibrationService(),
            bibleProgressService: _StubBibleProgressService(),
            readingPlanService: planService,
            userPreferencesService: prefsService,
            dateProvider: DateTime.now,
            enableDriftAnimation: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (find.bySemanticsLabel('Dismiss check-in').evaluate().isNotEmpty) {
        await tester.tap(find.bySemanticsLabel('Dismiss check-in'));
        await tester.pumpAndSettle();
      }

      // Coupling is already linked, so no SyncSheet should appear.
      await tester.tap(find.text('Mark as read'));
      await tester.pumpAndSettle();
      expect(find.text('Keep them separate'), findsNothing);

      // The habit was recorded in Firestore...
      final today = DateTime.now();
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final habitDoc = await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc(dateKey)
          .get();
      expect(habitDoc.data()?['read'], isTrue);

      // ...and the SunMark in header reflects it with marked state.
      expect(
        find.bySemanticsLabel('You read today — open check-in'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'group card mark, first-time "Yes" choice, marks the daily habit too',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1'),
        signedIn: true,
      );
      final groupService = GroupService(firestore: firestore);

      final groupId = await groupService.createGroup(
        ownerUid: 'u1',
        name: 'Test Group',
      );
      final today = DateTime.now();
      await groupService.updateSchedule(
        groupId: groupId,
        schedule: GroupSchedule(date: today, chapters: const ['John 1']),
      );

      await tester.pumpWidget(
        _host(
          HomePage(
            firestore: firestore,
            auth: auth,
            vibrationService: const VibrationService(),
            bibleProgressService: _StubBibleProgressService(),
            groupService: groupService,
            userPreferencesService: UserPreferencesService(
              firestore: firestore,
            ),
            dateProvider: DateTime.now,
            enableDriftAnimation: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (find.bySemanticsLabel('Dismiss check-in').evaluate().isNotEmpty) {
        await tester.tap(find.bySemanticsLabel('Dismiss check-in'));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('Read with your community'));
      await tester.pumpAndSettle();

      // First completion shows the one-time coupling prompt; choose "Yes".
      expect(find.text('Yes, count it as showing up'), findsOneWidget);
      await tester.tap(find.text('Yes, count it as showing up'));
      await tester.pumpAndSettle();

      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final habitDoc = await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc(dateKey)
          .get();
      expect(habitDoc.data()?['read'], isTrue);
      expect(
        find.bySemanticsLabel('You read today — open check-in'),
        findsOneWidget,
      );
    },
  );
}
