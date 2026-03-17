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
import 'package:bible_read/services/achievement_service.dart';
import 'package:bible_read/services/group_book_achievement_service.dart';
import 'package:bible_read/widgets/skeletons/home_page_skeleton.dart'; // Import for type check
import '../helpers/mock_lottie_http_client.dart';

class _StubVibrationService extends VibrationService {
  int lightCount = 0;

  @override
  Future<void> lightImpact() async {
    lightCount++;
  }
}

class _StubAchievementService extends AchievementService {
  _StubAchievementService() : super(firestore: FakeFirebaseFirestore());
}

class _StubGroupBookAchievementService extends GroupBookAchievementService {
  _StubGroupBookAchievementService()
      : super(firestore: FakeFirebaseFirestore());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    setupLottieHttpOverrides();
  });
  tearDownAll(resetHttpOverrides);

  testWidgets('show "How did your reading go today?" and button when not read', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );

    // Initial state: not read today
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: _StubVibrationService(),
          achievementService: _StubAchievementService(),
          groupBookAchievementService: _StubGroupBookAchievementService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('How did your reading go today?'), findsOneWidget);
    expect(find.text('Yes, I read'),
        findsOneWidget); // Can be FilledButton or FilledButton.tonal
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text('Thank you for being here.'), findsNothing);
  });

  testWidgets('show "Thank you for being here." when read today',
      (tester) async {
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
          achievementService: _StubAchievementService(),
          groupBookAchievementService: _StubGroupBookAchievementService(),
        ),
      ),
    );
    // Allow FutureBuilder/async loads to complete
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('Marked Today'), findsNothing);
    expect(find.text('Thank you for being here.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    expect(find.text('Yes, I read'), findsNothing);
  });

  testWidgets('tapping "Yes, I read" updates UI to read state', (tester) async {
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
          achievementService: _StubAchievementService(),
          groupBookAchievementService: _StubGroupBookAchievementService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial state
    expect(find.text('Yes, I read'), findsOneWidget);

    // Tap button
    await tester.tap(find.text('Yes, I read'));
    await tester.pump(); // Start animation/process

    // Expect loading state or immediate update (optimistic)
    await tester.pumpAndSettle();

    // Verify final state
    expect(find.text('Thank you for being here.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);

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

  testWidgets('displays streak and weekly progress', (tester) async {
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
          achievementService: _StubAchievementService(),
          groupBookAchievementService: _StubGroupBookAchievementService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify streak text (RichText)
    // RichText content aggregates to "5 days of reading"
    expect(find.text('5 days of reading', findRichText: true), findsOneWidget);

    // Verify progress bar elements
    expect(find.text('Reading this week'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
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
          achievementService: _StubAchievementService(),
          groupBookAchievementService: _StubGroupBookAchievementService(),
          readingStatusService: slowReadingService,
        ),
      ),
    );

    // Initial pump - should show skeleton immediately
    await tester.pump();

    // Check that regular content is NOT present yet
    expect(find.text('How did your reading go today?'), findsNothing);
    expect(find.text('Yes, I read'), findsNothing);

    // Check that Skeleton is present
    expect(find.byType(HomePageSkeleton), findsOneWidget);

    // Fast forward time to finish loading
    // The skeleton loader has a minTime of 500ms (default)
    // The service has a delay of 1s.
    // We pump for 1 second + buffer
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();

    // Now content should be visible
    expect(find.text('How did your reading go today?'), findsOneWidget);
    expect(find.byType(HomePageSkeleton), findsNothing);
  });
}

class MockReadingStatusService extends ReadingStatusService {
  MockReadingStatusService()
      : super(firestore: FakeFirebaseFirestore(), auth: MockFirebaseAuth());

  @override
  Future<ReadingStatus> fetchStatus() async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 1000));
    return ReadingStatus(
      readToday: false,
      pastWeek: [],
      pastMonth: [],
      readDates: {},
      streak: 0,
      graceCreditsAvailable: 0,
      graceCreditsMonth: '2021-01',
    );
  }
}
