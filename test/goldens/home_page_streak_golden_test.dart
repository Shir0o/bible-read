
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/services/reading_status_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/services/bible_progress_service.dart';
import '../helpers/path_provider_mock.dart';
import '../helpers/pump_golden.dart';
import '../helpers/mock_sqflite.dart';
import 'package:mocktail/mocktail.dart';

class _StubVibrationService extends VibrationService {
  @override
  Future<void> lightImpact() async {}
}

class _StubBibleProgressService extends BibleProgressService {
  _StubBibleProgressService() : super(firestore: FakeFirebaseFirestore());
}

void main() {
  setupPathProviderMocks();
  setupSqfliteMock();

  testWidgets('HomePage Streak Golden Test (Not Read Today - Streak Absent)', (tester) async {
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

    // Allow data to load
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Verify streak is ABSENT when not read today (new behavior)
    expect(find.textContaining('12', findRichText: true), findsNothing);
    expect(find.text('Reading this week'), findsNothing);

    await expectLater(
      find.byType(HomePage),
      matchesGoldenFile('goldens/home_page_streak_not_read.png'),
    );
  });

  testWidgets('HomePage Streak Golden Test (Read Today - Streak Visible)', (tester) async {
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
      'pastWeekReadDates': ['2024-07-28', '2024-07-29', '2024-07-30'], // Sun, Mon, Tue
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

    // Allow data to load
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Verify streak is VISIBLE when read today
    expect(find.textContaining('12', findRichText: true), findsOneWidget);
    expect(find.text('Reading this week'), findsOneWidget);

    await expectLater(
      find.byType(HomePage),
      matchesGoldenFile('goldens/home_page_streak_read.png'),
    );
  });
}
