import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/services/google_sign_in_factory.dart';
import 'package:bible_read/models/reading_plan.dart';
import '../test/helpers/fake_google_sign_in_platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('complete a daily reading journey', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final mockUser = MockUser(
      uid: 'u1',
      displayName: 'Test User',
      email: 'test@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
    final google = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = google;

    // 1. Setup initial data
    final now = DateTime.now();
    final plan = ReadingPlan(
      id: 'plan_1',
      title: 'Daily Journey Plan',
      description: 'Test Plan',
      durationDays: 30,
      tags: [],
      schedule: [
        ReadingPlanDay(day: 1, readings: ['Genesis 1']),
      ],
    );

    await firestore.collection('custom_plans').doc('plan_1').set(plan.toJson());
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

    // 2. Launch App
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

    await tester.pumpAndSettle(const Duration(milliseconds: 1500));

    // 3. Verify Home Page Content
    expect(find.text('Daily Journey Plan'), findsOneWidget);
    expect(find.text('Genesis 1'), findsOneWidget);

    // 4. Mark as Read
    await tester.tap(find.text('I have read'));
    await tester.pump();
    expect(find.text('Thank you for being here.'), findsOneWidget);

    // 5. Navigate to Journey Page to see progress
    await tester.tap(find.text('Journey'));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsAtLeast(1));

    // 6. Navigate to Community to confirm the tab loads.
    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle();
    expect(find.text('Community'), findsWidgets);
  });
}
