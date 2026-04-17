import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/services/google_sign_in_factory.dart';
import 'package:bible_read/models/reading_plan.dart';

class FakeGoogleSignInPlatform extends GoogleSignInPlatform
    with MockPlatformInterfaceMixin {
  GoogleSignInUserData? user;

  @override
  Future<void> init({
    List<String> scopes = const <String>[],
    SignInOption signInOption = SignInOption.standard,
    String? hostedDomain,
    String? clientId,
  }) async {}

  @override
  Future<GoogleSignInUserData?> signInSilently() async => user;

  @override
  Future<GoogleSignInUserData?> signIn() async => user;

  @override
  Future<GoogleSignInTokenData> getTokens({
    required String email,
    bool? shouldRecoverAuth,
  }) async {
    return GoogleSignInTokenData(
      idToken: 'id',
      accessToken: 'access',
    );
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> isSignedIn() async => user != null;

  @override
  Future<void> clearAuthCache({required String token}) async {}

  @override
  Future<bool> requestScopes(List<String> scopes) async => true;

  @override
  Future<bool> canAccessScopes(List<String> scopes,
          {String? accessToken}) async =>
      true;

  @override
  Stream<GoogleSignInUserData?>? get userDataEvents => null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('mark today as read on home page', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final mockUser = MockUser(
      uid: 'u1',
      displayName: 'Test User',
      email: 'test@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
    final google = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = google;

    // Use a fixed date for testing
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

    // Seed user preferences to auto-mark plan as read
    await firestore
        .collection('users')
        .doc('u1')
        .collection('settings')
        .doc('general')
        .set({
      'autoMarkPlanRead': true,
    });

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

    // Verify "I have read" button exists
    expect(find.text('I have read'), findsOneWidget);
    expect(find.byKey(const ValueKey('unread_state')), findsOneWidget);

    // 3. Tap "I have read"
    await tester.tap(find.text('I have read'));
    
    // 4. Verify Optimistic UI Update
    await tester.pump(); 
    // Should immediately show the "read_state"
    expect(find.byKey(const ValueKey('read_state')), findsOneWidget);
    expect(find.text('Thank you for being here.'), findsOneWidget);

    // 5. Verify Backend Confirmation
    await tester.pumpAndSettle();
    
    // Check Firestore directly
    final readDoc = await firestore
        .collection('users')
        .doc('u1')
        .collection('reading')
        .doc(todayKey)
        .get();
    
    expect(readDoc.exists, isTrue, reason: 'Reading document should be created in Firestore');
    expect(readDoc.data()?['read'], isTrue);

    // Check plan progress
    final progressDoc = await firestore
        .collection('users')
        .doc('u1')
        .collection('plan_progress')
        .doc('plan_1')
        .get();
    
    final completedDays = List<int>.from(progressDoc.data()?['completedDays'] ?? []);
    expect(completedDays, contains(1), reason: 'Day 1 should be marked as completed in the plan progress');
  });
}
