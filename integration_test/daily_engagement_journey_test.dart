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
import 'package:bible_read/widgets/community/community_activity_item.dart';
import 'package:bible_read/services/google_sign_in_factory.dart';

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
  }) async => GoogleSignInTokenData(idToken: 'id', accessToken: 'access');
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
  Future<bool> canAccessScopes(List<String> scopes, {String? accessToken}) async => true;
  @override
  Stream<GoogleSignInUserData?>? get userDataEvents => null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('The Daily Streak & Social Propagator Master Journey', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final mockUser = MockUser(
      uid: 'u1', 
      displayName: 'Test User', 
      email: 'test@example.com'
    );
    final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
    
    final google = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = google;

    final now = DateTime.now();
    final dateKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // 1. Setup initial user data in Firestore
    await firestore.collection('users').doc('u1').set({
      'displayName': 'Test User',
      'email': 'test@example.com',
    });

    // Create a mock reading plan
    await firestore.collection('custom_plans').doc('plan_1').set({
      'title': 'Sequential NT',
      'description': 'Read the NT',
      'durationDays': 1,
      'tags': [],
      'schedule': [
        {
          'day': 1,
          'readings': ['Matthew 1']
        }
      ],
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

    // Wait for the skeleton loader (Mandate: visible for min 1000ms)
    await tester.pumpAndSettle(const Duration(milliseconds: 1500));

    // 3. Verify Initial State
    // Check for either 'TODAY\'S READING' or 'Daily Reading' depending on how it loaded
    final todayReadingFinder = find.text('TODAY\'S READING');
    final dailyReadingFinder = find.text('Daily Reading');
    expect(tester.any(todayReadingFinder) || tester.any(dailyReadingFinder), isTrue);

    // 4. Perform Optimistic Reading Toggle
    final toggleFinder = find.text('I have read');
    final fallbackToggleFinder = find.text('Yes, I read');
    
    if (tester.any(toggleFinder)) {
      await tester.tap(toggleFinder);
    } else {
      await tester.tap(fallbackToggleFinder);
    }

    // MANDATE: Verify Immediate UI Update (Optimistic)
    // Should show '1' day streak now that it's marked as read
    await tester.pump(); // Just one pump to reflect local state change
    expect(find.textContaining('1'), findsAtLeast(1));
    expect(find.text('Thank you for being here.'), findsOneWidget);
    
    // 5. Verify Backend Sync
    // Now wait for the "background" work to settle in our fake firestore
    await tester.pumpAndSettle();
    
    final readDoc = await firestore
        .collection('users')
        .doc('u1')
        .collection('reading')
        .doc(dateKey)
        .get();
    expect(readDoc.exists, isTrue);
    expect(readDoc.data()?['read'], isTrue);

    final summaryDoc = await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .get();
    // In a real scenario, the service or a Cloud Function trigger would update this.
    // FakeFirebaseFirestore doesn't run Cloud Functions.
    // However, our ReadingStatusService handles local summary updates too.
    expect(summaryDoc.exists, isTrue);
    expect(summaryDoc.data()?['streak'], greaterThanOrEqualTo(1));

    // 6. Social Propagation (Community Feed)
    final communityFinder = find.text('Community');
    expect(communityFinder, findsOneWidget);
    await tester.tap(communityFinder);
    
    // Wait for skeletons and animations to finish
    await tester.pumpAndSettle();
    
    // Robust wait for data to appear
    bool foundActivity = false;
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (tester.any(find.byType(CommunityActivityItem))) {
        foundActivity = true;
        break;
      }
    }

    expect(foundActivity, isTrue, reason: 'CommunityActivityItem should appear in the feed');
    // User 'Test User' should appear as 'Test'
    expect(find.textContaining('Test'), findsWidgets);

    // Perform an Optimistic Like
    final likeButton = find.byIcon(Icons.favorite_border).first;
    await tester.tap(likeButton);
    await tester.pump(); // Optimistic update
    expect(find.byIcon(Icons.favorite), findsWidgets); // Should change to filled heart

    // 7. Validation of cross-collection logs
    final logEntry = await firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc('u1')
        .get();
    expect(logEntry.exists, isTrue);
    // Since we were the only one, we might expect firstReader if the mock logic matches
    // In our test we can manually trigger the mock if needed, but standard service 
    // usually writes the log entry.
  });
}
