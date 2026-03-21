
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/services/reading_status_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/services/bible_progress_service.dart';

class _StubVibrationService extends VibrationService {
  @override
  Future<void> lightImpact() async {}
}

class _StubBibleProgressService extends BibleProgressService {
  _StubBibleProgressService() : super(firestore: FakeFirebaseFirestore());
}

void main() {
  group('Validation of Streak and Week Bar fixes', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late ReadingStatusService service;
    late MockUser user;
    late DateTime fixedNow;

    setUp(() {
      user = MockUser(
        uid: 'user1',
        email: 'user1@test.com',
        displayName: 'User One',
      );
      auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      firestore = FakeFirebaseFirestore();
      fixedNow = DateTime(2024, 7, 30); // A Tuesday
      service = ReadingStatusService(
        firestore: firestore,
        auth: auth,
        nowProvider: () => fixedNow,
      );
    });

    test('Unit Test: updateSummary DOES NOT reset streak to 0 if today is not read yet', () async {
      final userDoc = firestore.collection('users').doc(user.uid);
      await userDoc.set({'email': user.email});

      String formatDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      // Day -5: Read (S1)
      // Day -4: Miss (S2 - credit 1 used)
      // Day -3: Miss (S3 - credit 2 used)
      // Day -2: Read (S4)
      // Day -1: Read (S5)
      // Today: Not read (Should STAY S5)

      await userDoc.collection('reading').doc(formatDate(fixedNow.subtract(const Duration(days: 5)))).set({'read': true});
      // Miss -4
      // Miss -3
      await userDoc.collection('reading').doc(formatDate(fixedNow.subtract(const Duration(days: 2)))).set({'read': true});
      await userDoc.collection('reading').doc(formatDate(fixedNow.subtract(const Duration(days: 1)))).set({'read': true});

      final stats = await service.updateSummary();
      
      expect(stats.streak, 5, reason: 'Streak should not reset to 0 if today is not read yet');
      expect(stats.graceCreditsAvailable, 0);
    });

    testWidgets('Widget Test: Streak and Week Bar are VISIBLE even if not read today', (tester) async {
      // Seed summary data with a streak
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('summary')
          .doc('data')
          .set({
        'streak': 5,
        'pastWeekReadDates': [],
      });

      // NOT read today.
      
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            firestore: firestore,
            auth: auth,
            vibrationService: _StubVibrationService(),
            bibleProgressService: _StubBibleProgressService(),
            dateProvider: () => fixedNow,
            readingStatusService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify streak text and progress bar are ABSENT (now only shown after read)
      expect(find.textContaining('5', findRichText: true), findsNothing);
      expect(find.text('Reading this week'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });
}
