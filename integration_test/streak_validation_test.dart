import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/services/reading_status_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('streak and weekly progress validation flow', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1', displayName: 'Test User');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final fixedNow = DateTime(2024, 7, 30); // A Tuesday

    // 1. Seed initial data: 5 day streak up to yesterday (Monday)
    // Dates: Thu 25, Fri 26, Sat 27, Sun 28, Mon 29
    final dates = [
      '2024-07-25',
      '2024-07-26',
      '2024-07-27',
      '2024-07-28',
      '2024-07-29',
    ];

    for (final date in dates) {
      await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc(date)
          .set({'read': true});
    }

    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({
      'streak': 5,
      'pastWeekReadDates': [
        '2024-07-28',
        '2024-07-29'
      ], // Sun, Mon (this calendar week)
      'graceCreditsAvailable': 0,
    });

    final service = ReadingStatusService(
      firestore: firestore,
      auth: auth,
      nowProvider: () => fixedNow,
    );

    // 2. Launch HomePage
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(
            firestore: firestore,
            auth: auth,
            dateProvider: () => fixedNow,
            readingStatusService: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 3. Verify streak and week bar are ABSENT before reading (new behavior)
    expect(find.textContaining('5', findRichText: true), findsNothing);
    expect(find.text('Reading this week'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    // 4. Mark today as read
    final readButton = find.text('Yes, I read');
    expect(readButton, findsOneWidget);
    await tester.tap(readButton);

    // Wait for optimistic update and backend sync
    await tester.pump();
    await tester.pumpAndSettle();

    // 5. Verify streak and week bar ARE NOW VISIBLE and updated
    expect(find.textContaining('6', findRichText: true), findsOneWidget);
    expect(find.text('Reading this week'), findsOneWidget);

    // 6. Verify weekly progress bar updated to 3/7 (Sun, Mon, Tue)
    final progressIndicatorAfter = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(progressIndicatorAfter.value, closeTo(3 / 7, 0.01));

    // 7. Verify "Thank you" message
    expect(find.text('Thank you for being here.'), findsOneWidget);
  });
}
