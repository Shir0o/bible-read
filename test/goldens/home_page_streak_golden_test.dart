import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/services/reading_status_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/services/bible_progress_service.dart';
import '../helpers/path_provider_mock.dart';
import '../helpers/pump_golden.dart';
import '../helpers/mock_sqflite.dart';

class _StubVibrationService extends VibrationService {
  @override
  Future<void> lightImpact() async {}
}

class _StubBibleProgressService extends BibleProgressService {
  _StubBibleProgressService() : super(firestore: FakeFirebaseFirestore());
}

/// Loads the Home data + settles the habit-hero AnimatedSwitcher. The home page
/// streams never emit under FakeFirebaseFirestore, so the load completes via the
/// `_firstWithTimeout` fallbacks (~a few seconds of fake time); timed pumps
/// advance the clock past them and finish the 500ms animation.
Future<void> _settleHome(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (!tester.binding.hasScheduledFrame) break;
  }
}

void main() {
  setupPathProviderMocks();
  setupSqfliteMock();

  // Back sqflite's global databaseFactory with the FFI (in-process) factory so
  // cached_network_image's cache lookup works in the headless test env instead
  // of throwing "databaseFactory not initialized".
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('HomePage Streak Golden Test (Not Read Today - Streak Absent)', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final fixedNow = DateTime(2024, 7, 30);

    // Seed summary data with a streak
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({
      'streak': 12,
      'totalReadDays': 12,
      'pastWeekReadDates': ['2024-07-28', '2024-07-29'], // Sun, Mon
      'graceCreditsAvailable': 0,
    });

    final service = ReadingStatusService(
      firestore: firestore,
      auth: auth,
      nowProvider: () => fixedNow,
    );

    await tester.pumpGolden(
      HomePage(
        firestore: firestore,
        auth: auth,
        vibrationService: _StubVibrationService(),
        bibleProgressService: _StubBibleProgressService(),
        dateProvider: () => fixedNow,
        readingStatusService: service,
      ),
      brightness: Brightness.light,
    );

    await _settleHome(tester);

    // The consistency glimpse ("Here N days this season") only surfaces once the
    // user has shown up today, so it is absent here.
    expect(find.textContaining('this season'), findsNothing);

    await expectLater(
      find.byType(HomePage),
      matchesGoldenFile('goldens/home_page_streak_not_read.png'),
    );
  });

  testWidgets('HomePage Streak Golden Test (Read Today - Streak Visible)', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final fixedNow = DateTime(2024, 7, 30);

    // Seed summary data with a streak
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({
      'streak': 12,
      'totalReadDays': 12,
      'pastWeekReadDates': [
        '2024-07-28',
        '2024-07-29',
        '2024-07-30',
      ], // Sun, Mon, Tue
      'graceCreditsAvailable': 0,
    });

    final service = ReadingStatusService(
      firestore: firestore,
      auth: auth,
      nowProvider: () => fixedNow,
    );

    // Seed "read" status for today
    final todayKey = '2024-07-30';
    await firestore
        .collection('users')
        .doc('u1')
        .collection('reading')
        .doc(todayKey)
        .set({'read': true});

    await tester.pumpGolden(
      HomePage(
        firestore: firestore,
        auth: auth,
        vibrationService: _StubVibrationService(),
        bibleProgressService: _StubBibleProgressService(),
        dateProvider: () => fixedNow,
        readingStatusService: service,
      ),
      brightness: Brightness.light,
    );

    await _settleHome(tester);

    // Once read today, the consistency glimpse surfaces the season day count.
    expect(find.text('Here 12 days this season'), findsOneWidget);

    await expectLater(
      find.byType(HomePage),
      matchesGoldenFile('goldens/home_page_streak_read.png'),
    );
  });
}
