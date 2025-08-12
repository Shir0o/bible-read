// ignore_for_file: depend_on_referenced_packages
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/read_log_page.dart';
import 'package:bible_read/pages/friends_page.dart';
import 'package:bible_read/pages/achievements_page.dart';
import 'package:bible_read/widgets/responsive_scaffold.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:bible_read/services/daily_notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';

class FakeGoogleSignInPlatform extends GoogleSignInPlatform
    with MockPlatformInterfaceMixin {
  GoogleSignInUserData? user;
  int silentSignInCount = 0;

  @override
  Future<void> init({
    List<String> scopes = const <String>[],
    SignInOption signInOption = SignInOption.standard,
    String? hostedDomain,
    String? clientId,
  }) async {}

  @override
  Future<GoogleSignInUserData?> signInSilently() async {
    silentSignInCount++;
    return user;
  }

  @override
  Future<GoogleSignInUserData?> signIn() async => user;

  @override
  Future<GoogleSignInTokenData> getTokens({
    required String email,
    bool? shouldRecoverAuth,
  }) async {
    return GoogleSignInTokenData(
      idToken: 'idToken',
      accessToken: 'accessToken',
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
  Future<bool> canAccessScopes(
    List<String> scopes, {
    String? accessToken,
  }) async => true;

  @override
  Stream<GoogleSignInUserData?>? get userDataEvents => null;
}

class FakeFirebaseMessaging extends Fake implements FirebaseMessaging {
  FakeFirebaseMessaging(this.token);
  final String? token;

  @override
  Future<String?> getToken({String? vapidKey}) async => token;
}

class RecordingNotificationService extends DailyNotificationService {
  bool scheduled = false;

  RecordingNotificationService({required FirebaseAuth auth})
    : super(auth: auth);

  @override
  Future<bool> scheduleDailyReminder(Time time) async {
    scheduled = true;
    return true;
  }
}

class FakeNotificationsPlatform extends FlutterLocalNotificationsPlatform {
  int? canceledId;

  @override
  Future<void> cancel(int id) async {
    canceledId = id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  late FakeGoogleSignInPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = fakePlatform;
  });

  testWidgets('MainPage navigation to profile', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          dailyNotificationServiceProvider: DailyNotificationService.new,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Profile should be shown by default when not authenticated
    expect(find.text('Sign in with Google'), findsOneWidget);

    // Profile should be shown when tapping profile or if it's the only page.
    if (find.byIcon(Icons.person).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.person));
      await tester.pumpAndSettle();
    }
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('navigation updates selected index', (tester) async {
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          firestore: firestore,
          messaging: FakeFirebaseMessaging(null),
          dailyNotificationServiceProvider: DailyNotificationService.new,
        ),
      ),
    );
    expect(find.byType(AnimatedSwitcher), findsOneWidget);
    await tester.tap(find.byIcon(Icons.feed));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(AnimatedSwitcher),
        matching: find.byType(FadeTransition),
      ),
      findsWidgets,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ReadLogPage), findsOneWidget);

    // Friends navigation via drawer
    final responsive = tester.widget<ResponsiveScaffold>(
      find.byType(ResponsiveScaffold),
    );
    responsive.scaffoldKey!.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.people));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(AnimatedSwitcher),
        matching: find.byType(FadeTransition),
      ),
      findsWidgets,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(FriendsPage), findsOneWidget);

    // Achievements navigation via drawer
    responsive.scaffoldKey!.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.emoji_events));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(AnimatedSwitcher),
        matching: find.byType(FadeTransition),
      ),
      findsWidgets,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AchievementsPage), findsOneWidget);
  });

  testWidgets('attemptSilentSignIn runs during initState', (tester) async {
    fakePlatform.user = GoogleSignInUserData(
      email: 'test@example.com',
      id: '123',
      displayName: 'Test',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          dailyNotificationServiceProvider: DailyNotificationService.new,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fakePlatform.silentSignInCount, 1);
  });

  testWidgets('responsive scaffold switches layout', (tester) async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'u1'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(800, 600)),
          child: MainPage(
            auth: auth,
            dailyNotificationServiceProvider: DailyNotificationService.new,
          ),
        ),
      ),
    );
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(400, 600)),
          child: MainPage(
            auth: auth,
            dailyNotificationServiceProvider: DailyNotificationService.new,
          ),
        ),
      ),
    );
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('unauthenticated navigation restricted to profile', (
    tester,
  ) async {
    final auth = MockFirebaseAuth();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 600)),
          child: MainPage(
            auth: auth,
            dailyNotificationServiceProvider: DailyNotificationService.new,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNothing);
    expect(find.text('Sign in with Google'), findsOneWidget);

    final scaffold = tester.widget<ResponsiveScaffold>(
      find.byType(ResponsiveScaffold),
    );

    scaffold.onDestinationSelected(1);
    await tester.pump();

    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('saves FCM token to Firestore on silent sign-in', (tester) async {
    fakePlatform.user = GoogleSignInUserData(
      email: 'test@example.com',
      id: '123',
      displayName: 'Test',
    );

    final fakeFirestore = FakeFirebaseFirestore();
    final testUser = MockUser(uid: 'u123');
    final auth = MockFirebaseAuth(mockUser: testUser, signedIn: true);
    final messaging = FakeFirebaseMessaging('test_token');

    // Insert a dummy user doc
    await fakeFirestore.collection('users').doc(testUser.uid).set({});

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          firestore: fakeFirestore,
          messaging: messaging,
          dailyNotificationServiceProvider: DailyNotificationService.new,
        ),
      ),
    );

    await tester.pumpAndSettle();

    final userDoc = await fakeFirestore
        .collection('users')
        .doc(testUser.uid)
        .get();

    expect(userDoc.exists, isTrue);
    expect(userDoc.data()!.containsKey('fcmToken'), isTrue);
  });

  testWidgets('schedules reminder when user already signed in', (tester) async {
    fakePlatform.user = null;
    final fakeFirestore = FakeFirebaseFirestore();
    final testUser = MockUser(uid: 'u-signin');
    final auth = MockFirebaseAuth(mockUser: testUser, signedIn: true);
    final messaging = FakeFirebaseMessaging('tok');
    final service = RecordingNotificationService(auth: auth);

    await fakeFirestore.collection('users').doc(testUser.uid).set({});

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          firestore: fakeFirestore,
          messaging: messaging,
          dailyNotificationServiceProvider: () => service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.scheduled, isTrue);
  });
  testWidgets('calls sendLikeNotification when a like is triggered', (
    tester,
  ) async {
    bool wasCalled = false;
    String? calledUid;
    String? calledName;

    final fakeFirestore = FakeFirebaseFirestore();
    final testUser = MockUser(uid: 'liker123', displayName: 'Test Liker');
    final auth = MockFirebaseAuth(mockUser: testUser, signedIn: true);

    // Insert a dummy user doc to like
    await fakeFirestore.collection('users').doc('owner456').set({});

    // Add a read log entry for 'owner456'
    final dateKey =
        '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    await fakeFirestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc('owner456')
        .set({'name': 'Owner User', 'timestamp': Timestamp.now()});

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          firestore: fakeFirestore,
          messaging: FakeFirebaseMessaging(null),
          dailyNotificationServiceProvider: DailyNotificationService.new,
          sendLikeNotification:
              ({required String ownerUid, required String likerName}) async {
                wasCalled = true;
                calledUid = ownerUid;
                calledName = likerName;
              },
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Navigate to Feed (ReadLogPage)
    await tester.tap(find.byIcon(Icons.feed));
    await tester.pumpAndSettle();

    // Find the ListTile for 'Owner User' and tap the like button
    final ownerLogFinder = find.byWidgetPredicate(
      (widget) =>
          widget is ListTile &&
          widget.title is Text &&
          (widget.title as Text).data == 'Owner read today!',
    );
    expect(ownerLogFinder, findsOneWidget);

    await tester.tap(
      find.descendant(
        of: ownerLogFinder,
        matching: find.byIcon(Icons.favorite_border),
      ),
    );
    await tester.pumpAndSettle();

    expect(wasCalled, isTrue);
    expect(calledUid, 'owner456');
    expect(calledName, 'Test');
  });

  testWidgets('shows error page when appCheckFailed is true', (tester) async {
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          appCheckFailed: true,
          dailyNotificationServiceProvider: DailyNotificationService.new,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('App verification failed'), findsOneWidget);
    expect(find.byType(ResponsiveScaffold), findsNothing);
  });

  testWidgets('signing out returns to profile and restricts navigation', (
    tester,
  ) async {
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    fakePlatform.user = GoogleSignInUserData(
      email: 'test@example.com',
      id: '123',
      displayName: 'Test',
    );
    final fakeNotifications = FakeNotificationsPlatform();
    FlutterLocalNotificationsPlatform.instance = fakeNotifications;
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          firestore: firestore,
          messaging: FakeFirebaseMessaging(null),
          dailyNotificationServiceProvider: DailyNotificationService.new,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Navigate to a different page first
    await tester.tap(find.byIcon(Icons.feed));
    await tester.pumpAndSettle();
    expect(find.byType(ReadLogPage), findsOneWidget);

    // Go to profile and sign out
    final responsive = tester.widget<ResponsiveScaffold>(
      find.byType(ResponsiveScaffold),
    );
    responsive.scaffoldKey!.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();

    // Should now show the unauthenticated profile page
    expect(find.text('Sign in with Google'), findsOneWidget);

    final scaffold = tester.widget<ResponsiveScaffold>(
      find.byType(ResponsiveScaffold),
    );
    expect(scaffold.destinations.length, 1);
    expect(find.byIcon(Icons.home), findsNothing);
    expect(find.byIcon(Icons.feed), findsNothing);
    expect(find.byIcon(Icons.leaderboard), findsNothing);
    expect(find.byIcon(Icons.people), findsNothing);

    scaffold.onDestinationSelected(1);
    await tester.pump();

    expect(find.text('Sign in with Google'), findsOneWidget);
  });
}
