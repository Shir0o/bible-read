import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/services/google_sign_in_factory.dart';
import 'package:bible_read/models/reading_plan.dart';
import 'helpers/fake_google_sign_in_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('mark today as read on home page (widget test)', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final mockUser = MockUser(
      uid: 'u1',
      displayName: 'Test User',
      email: 'test@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
    final google = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = google;

    // Use current date for testing logic
    final now = DateTime.now();
    String formatDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final todayKey = formatDate(now);

    // 1. Setup a reading plan for the user
    final plan = ReadingPlan(
      id: 'plan_1',
      title: 'Test Plan',
      description: 'A plan for testing',
      durationDays: 30,
      tags: [],
      schedule: [
        ReadingPlanDay(day: 1, readings: ['Genesis 1']),
      ],
    );

    // Save the plan to custom_plans
    await firestore.collection('custom_plans').doc('plan_1').set({
      ...plan.toJson(),
      'userId': 'u1',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Set the user's active plan progress starting today
    await firestore
        .collection('users')
        .doc('u1')
        .collection('plan_progress')
        .doc('plan_1')
        .set({
      'planId': 'plan_1',
      'userId': 'u1',
      'startDate': Timestamp.fromDate(now),
      'completedDays': [],
      'isArchived': false,
    });

    // Initialize summary data
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({
      'streak': 0,
      'totalReadDays': 0,
      'pastWeekReadDates': [],
      'pastMonthReadDates': [],
    });

    // Seed "Reading counts as showing up" ON. Coupling is one-directional, so
    // even with this enabled the bare habit tap must NOT advance the plan.
    await firestore
        .collection('users')
        .doc('u1')
        .collection('settings')
        .doc('general')
        .set({'autoMarkPlanRead': true, 'syncPromptAnswered': true});

    // 2. Launch the app
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: MainPage(
          firestore: firestore,
          auth: auth,
          googleSignInProvider: createGoogleSignIn,
        ),
      ),
    );

    // Wait for initial data loading and skeleton loaders
    await tester.pumpAndSettle(const Duration(milliseconds: 1500));

    // Verify the habit hero "I read today" button exists
    expect(find.text('I read today'), findsOneWidget);
    expect(find.byKey(const ValueKey('habit_todo')), findsOneWidget);

    // 3. Tap "I read today"
    await tester.tap(find.text('I read today'));

    // 4. Verify Optimistic UI Update
    await tester.pump();
    // Should immediately show the affirmation (read) state
    expect(find.byKey(const ValueKey('habit_done')), findsOneWidget);
    expect(find.text('Thank you for being here'), findsOneWidget);

    // 5. Verify Backend Confirmation
    await tester.pumpAndSettle();

    // Check Firestore directly
    final readDoc = await firestore
        .collection('users')
        .doc('u1')
        .collection('reading')
        .doc(todayKey)
        .get();

    expect(
      readDoc.exists,
      isTrue,
      reason: 'Reading document should be created in Firestore',
    );
    expect(readDoc.data()?['read'], isTrue);

    // Check plan progress
    final progressDoc = await firestore
        .collection('users')
        .doc('u1')
        .collection('plan_progress')
        .doc('plan_1')
        .get();

    final completedDays = List<int>.from(
      progressDoc.data()?['completedDays'] ?? [],
    );
    expect(
      completedDays,
      isEmpty,
      reason: 'The habit tap must never advance the plan (one-directional '
          'coupling); only finishing a plan reading may record the habit.',
    );
  });
}
