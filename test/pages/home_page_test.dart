// ignore_for_file: subtype_of_sealed_class

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/services/reading_status_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/services/bible_progress_service.dart';
import 'package:bible_read/services/reading_plan_service.dart';
import 'package:bible_read/services/user_preferences_service.dart';
import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/models/reading_plan_progress.dart';
import 'package:bible_read/models/user_preferences.dart';
import 'package:bible_read/widgets/skeletons/home_page_skeleton.dart'; // Import for type check
import '../helpers/mock_lottie_http_client.dart';

class _StubVibrationService extends VibrationService {
  int lightCount = 0;

  @override
  Future<void> lightImpact() async {
    lightCount++;
  }
}

class _StubBibleProgressService extends BibleProgressService {
  _StubBibleProgressService() : super(firestore: FakeFirebaseFirestore());
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
    'show "How did your reading go today?" and button when not read',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1'),
        signedIn: true,
      );

      // Initial state: not read today, auto-opens CheckInPage
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            firestore: firestore,
            auth: auth,
            vibrationService: _StubVibrationService(),
            bibleProgressService: _StubBibleProgressService(),
            dateProvider: () => DateTime.now(),
            enableDriftAnimation: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // CheckInPage is presented automatically
      expect(find.text('Did you read today?'), findsOneWidget);
      expect(find.text('I READ'), findsOneWidget);

      // Dismiss CheckInPage back to Home
      final dismissBtn = find.bySemanticsLabel('Dismiss check-in');
      await tester.tap(dismissBtn);
      await tester.pumpAndSettle();

      expect(find.text('Did you read today?'), findsNothing);
    },
  );

  testWidgets('show "Thank you for being here" on CheckInPage when read today',
      (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );

    // Pre-populate read status for today
    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    await firestore
        .collection('users')
        .doc('u1')
        .collection('reading')
        .doc(dateKey)
        .set({'read': true});

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: _StubVibrationService(),
          bibleProgressService: _StubBibleProgressService(),
          dateProvider: () => DateTime.now(),
          enableDriftAnimation: false,
        ),
      ),
    );
    // Allow FutureBuilder/async loads to complete
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // Today is read so CheckInPage does not auto-open.
    // Tap the SunMark icon in the header to open CheckInPage.
    final sunMark = find.bySemanticsLabel('You read today — open check-in');
    expect(sunMark, findsOneWidget);
    await tester.tap(sunMark);
    await tester.pumpAndSettle();

    expect(find.text('Thank you for being here'), findsOneWidget);
  });

  testWidgets('tapping "I READ" on CheckInPage updates UI to read state', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    final vibrationService = _StubVibrationService();

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: vibrationService,
          bibleProgressService: _StubBibleProgressService(),
          dateProvider: () => DateTime.now(),
          enableDriftAnimation: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial state on auto-opened CheckInPage
    expect(find.text('I READ'), findsOneWidget);

    // Tap I READ
    await tester.tap(find.text('I READ'));
    await tester.pump(); // Start animation
    await tester.pumpAndSettle();

    // Verify payoff screen state
    expect(find.text('Thank you for being here'), findsOneWidget);

    // Verify Firestore was updated
    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final doc = await firestore
        .collection('users')
        .doc('u1')
        .collection('reading')
        .doc(dateKey)
        .get();

    expect(doc.exists, isTrue);
    expect(doc.data()?['read'], isTrue);
  });

  testWidgets('displays the consistency glimpse', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );

    // Seed summary data with a streak
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({
      'streak': 5,
      'totalReadDays': 5,
      'pastWeekReadDates': [], // Empty for now
    });

    // Also mark as read today so the streak UI is visible
    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    await firestore
        .collection('users')
        .doc('u1')
        .collection('reading')
        .doc(dateKey)
        .set({'read': true});

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: _StubVibrationService(),
          bibleProgressService: _StubBibleProgressService(),
          dateProvider: () => DateTime.now(),
          enableDriftAnimation: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The consistency glimpse summarises showing up across the season using
    // the seeded totalReadDays (5), and links to Journey.
    expect(find.text('Here 5 days this season'), findsOneWidget);
    expect(find.text("Whenever you return, it's enough."), findsOneWidget);
  });

  testWidgets('displays skeleton while loading', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );

    // Create a slow service to simulate loading delay
    final slowReadingService = MockReadingStatusService();

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: _StubVibrationService(),
          bibleProgressService: _StubBibleProgressService(),
          readingStatusService: slowReadingService,
          dateProvider: () => DateTime.now(),
          enableDriftAnimation: false,
        ),
      ),
    );

    // Initial pump - should show skeleton immediately
    await tester.pump();

    // Check that regular content is NOT present yet
    expect(find.text('Did you read today?'), findsNothing);
    expect(find.text('I READ'), findsNothing);

    // Check that Skeleton is present
    expect(find.byType(HomePageSkeleton), findsOneWidget);

    // Fast forward time to finish loading
    // The skeleton loader has a minTime of 500ms (default)
    // The service has a delay of 1s.
    // We pump for 1 second + buffer
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();

    expect(find.text('Did you read today?'), findsOneWidget);
    expect(find.byType(HomePageSkeleton), findsNothing);
  });

  testWidgets('habit tap never advances the plan, even when coupling is on', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );

    // 1. Create a plan
    const plan = ReadingPlan(
      id: 'p1',
      title: 'Plan 1',
      description: 'Desc',
      durationDays: 30,
      tags: [],
      schedule: [
        ReadingPlanDay(day: 1, readings: ['Gen 1']),
        ReadingPlanDay(day: 2, readings: ['Gen 2']),
      ],
    );
    await firestore.collection('custom_plans').doc('p1').set({
      ...plan.toJson(),
      'userId': 'u1',
    });

    // 2. Start the plan for user
    final planService = ReadingPlanService(firestore: firestore);
    await planService.startPlan('u1', 'p1', startDate: DateTime.now());

    final prefsService = UserPreferencesService(firestore: firestore);

    // Test CASE 1: Preference is OFF (default)
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: _StubVibrationService(),
          bibleProgressService: _StubBibleProgressService(),
          readingPlanService: planService,
          userPreferencesService: prefsService,
          dateProvider: () => DateTime.now(),
          enableDriftAnimation: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap the CheckInPage "I READ" sun button
    await tester.tap(find.text('I READ'));
    await tester.pumpAndSettle();

    // Verify UI updated, NO prompt shown
    expect(find.text('Update Reading Plan?'), findsNothing);
    expect(find.text('Thank you for being here'), findsOneWidget);

    // Verify plan progress was NOT updated (since pref is false by default)
    var progressDoc = await firestore
        .collection('users')
        .doc('u1')
        .collection('plan_progress')
        .doc('p1')
        .get();
    var progress = UserPlanProgress.fromFirestore(progressDoc);
    expect(progress.completedDays, isEmpty);

    // Test CASE 2: Preference is ON
    await prefsService.updatePreferences(
      'u1',
      const UserPreferences(autoMarkPlanRead: true),
    );

    // Reset read status for today to allow re-testing on "same day" in test
    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    await firestore
        .collection('users')
        .doc('u1')
        .collection('reading')
        .doc(dateKey)
        .delete();

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          key: UniqueKey(),
          firestore: firestore,
          auth: auth,
          vibrationService: _StubVibrationService(),
          bibleProgressService: _StubBibleProgressService(),
          readingPlanService: planService,
          userPreferencesService: prefsService,
          dateProvider: () => DateTime.now(),
          enableDriftAnimation: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Tap the CheckInPage "I READ" sun button again
    await tester.tap(find.text('I READ'));
    await tester.pumpAndSettle();

    // Verify UI updated, NO prompt
    expect(find.text('Update Reading Plan?'), findsNothing);

    // Coupling is one-directional: the bare habit tap must NOT advance the
    // plan even when "Reading counts as showing up" is on. Only finishing a
    // plan reading may record the habit (the reverse direction).
    progressDoc = await firestore
        .collection('users')
        .doc('u1')
        .collection('plan_progress')
        .doc('p1')
        .get();
    progress = UserPlanProgress.fromFirestore(progressDoc);
    expect(progress.completedDays, isEmpty);
  });
}

class MockReadingStatusService extends ReadingStatusService {
  MockReadingStatusService()
      : super(firestore: FakeFirebaseFirestore(), auth: MockFirebaseAuth());

  @override
  Future<ReadingStatus> fetchStatus({bool forceRefresh = false}) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 1000));
    return ReadingStatus(
      readToday: false,
      pastWeek: [],
      pastMonth: [],
      readDates: {},
      streak: 0,
      totalReadDays: 0,
      graceCreditsAvailable: 0,
      graceCreditsMonth: '2021-01',
    );
  }
}
