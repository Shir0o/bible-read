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
import 'package:bible_read/pages/streak_history_page.dart';
import 'package:bible_read/pages/leaderboard_page.dart';
import 'package:bible_read/widgets/responsive_scaffold.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:bible_read/services/daily_notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_read/services/vibration_service.dart';

import '../helpers/test_read_log_page.dart';

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
  }) async =>
      true;

  @override
  Stream<GoogleSignInUserData?>? get userDataEvents => null;
}

class FakeFirebaseMessaging extends Fake implements FirebaseMessaging {
  FakeFirebaseMessaging(this.token);
  final String? token;

  @override
  Future<String?> getToken({String? vapidKey}) async => token;

  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) async {
    return const NotificationSettings(
      alert: AppleNotificationSetting.enabled,
      announcement: AppleNotificationSetting.enabled,
      authorizationStatus: AuthorizationStatus.authorized,
      badge: AppleNotificationSetting.enabled,
      carPlay: AppleNotificationSetting.enabled,
      lockScreen: AppleNotificationSetting.enabled,
      notificationCenter: AppleNotificationSetting.enabled,
      showPreviews: AppleShowPreviewSetting.always,
      timeSensitive: AppleNotificationSetting.enabled,
      criticalAlert: AppleNotificationSetting.enabled,
      sound: AppleNotificationSetting.enabled,
      providesAppNotificationSettings: AppleNotificationSetting.disabled,
    );
  }
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

class _RecordingVibrationService extends VibrationService {
  int lightCount = 0;
  int? indexDuringCall;
  int Function()? getIndex;

  @override
  Future<void> lightImpact() async {
    indexDuringCall = getIndex?.call();
    lightCount++;
  }
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
    SharedPreferences.setMockInitialValues({});
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

  testWidgets('tapping protected drawer item when signed out has no effect', (
    tester,
  ) async {
    final auth = MockFirebaseAuth();
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          dailyNotificationServiceProvider: DailyNotificationService.new,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Attempt to navigate to a protected page via the drawer.
    final responsive = tester.widget<ResponsiveScaffold>(
      find.byType(ResponsiveScaffold),
    );
    responsive.scaffoldKey!.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.people));
    await tester.pumpAndSettle();

    // The profile page should remain visible and navigation index unchanged.
    final state = tester.state(find.byType(MainPage)) as dynamic;
    expect(state.selectedIndex, 0);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('navigation updates selected index', (tester) async {
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(400, 600)),
        child: MaterialApp(
          home: MainPage(
            auth: auth,
            firestore: firestore,
            messaging: FakeFirebaseMessaging(null),
            dailyNotificationServiceProvider: DailyNotificationService.new,
          ),
        ),
      ),
    );
    expect(find.byType(IndexedStack), findsOneWidget);
    var responsive = tester.widget<ResponsiveScaffold>(
      find.byType(ResponsiveScaffold),
    );
    expect(responsive.contentIndex, 0);

    await tester.tap(find.byIcon(Icons.feed));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ReadLogPage), findsOneWidget);
    responsive = tester.widget<ResponsiveScaffold>(
      find.byType(ResponsiveScaffold),
    );
    expect(responsive.contentIndex, 1);

    // Friends navigation via drawer
    responsive.scaffoldKey!.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.people));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(FriendsPage), findsOneWidget);
    responsive = tester.widget<ResponsiveScaffold>(
      find.byType(ResponsiveScaffold),
    );
    expect(responsive.contentIndex, 3);

    // Achievements navigation via drawer
    responsive.scaffoldKey!.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.emoji_events));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AchievementsPage), findsOneWidget);
    responsive = tester.widget<ResponsiveScaffold>(
      find.byType(ResponsiveScaffold),
    );
    expect(responsive.contentIndex, 5);

    // History navigation via drawer
    responsive.scaffoldKey!.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_today));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(StreakHistoryPage), findsOneWidget);
    responsive = tester.widget<ResponsiveScaffold>(
      find.byType(ResponsiveScaffold),
    );
    expect(responsive.contentIndex, 6);
  });

  testWidgets('bottom navigation hidden on non-core pages', (tester) async {
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
    await tester.pumpAndSettle();

    final hasNav = find.byType(NavigationBar).evaluate().isNotEmpty ||
        find.byType(NavigationRail).evaluate().isNotEmpty;
    expect(hasNav, isTrue);

    final state = tester.state(find.byType(MainPage)) as dynamic;
    state.navigateFromMenu(3);
    await tester.pumpAndSettle();

    expect(find.byType(FriendsPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('bottom navigation hidden when navigating to leaderboard', (
    tester,
  ) async {
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: MainPage(
            auth: auth,
            firestore: firestore,
            messaging: FakeFirebaseMessaging(null),
            dailyNotificationServiceProvider: DailyNotificationService.new,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify the bottom navigation bar is initially visible.
    expect(find.byType(NavigationBar), findsOneWidget);

    final state = tester.state(find.byType(MainPage)) as dynamic;
    state.navigateFromMenu(2);
    await tester.pumpAndSettle();

    expect(find.byType(LeaderboardPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('_navigateFromMenu triggers vibration before updating index',
      (tester) async {
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    final vibration = _RecordingVibrationService();
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          firestore: FakeFirebaseFirestore(),
          vibrationService: vibration,
          messaging: FakeFirebaseMessaging(null),
          dailyNotificationServiceProvider: DailyNotificationService.new,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(MainPage)) as dynamic;
    vibration.getIndex = () => state.selectedIndex;

    state.navigateFromMenu(3);
    await tester.pump();

    expect(vibration.lightCount, 1);
    expect(vibration.indexDuringCall, 0);
    expect(state.selectedIndex, 3);
  });

  testWidgets('_navigateFromMenu does not vibrate when navigation blocked',
      (tester) async {
    final auth = MockFirebaseAuth();
    final vibration = _RecordingVibrationService();
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          firestore: FakeFirebaseFirestore(),
          vibrationService: vibration,
          messaging: FakeFirebaseMessaging(null),
          dailyNotificationServiceProvider: DailyNotificationService.new,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(MainPage)) as dynamic;
    state.navigateFromMenu(3);
    await tester.pump();

    expect(vibration.lightCount, 0);
    expect(state.selectedIndex, 0);
  });

  testWidgets('onItemTapped refreshes read log page', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    late TestReadLogPage testPage;

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          firestore: firestore,
          auth: auth,
          messaging: FakeFirebaseMessaging(null),
          readLogPageBuilder: ({
            Key? key,
            FirebaseFirestore? firestore,
            FirebaseAuth? auth,
            required SendLikeNotification onSendLikeNotification,
            required SendCommentNotification onSendCommentNotification,
          }) {
            return testPage = TestReadLogPage(
              key: key,
              firestore: firestore,
              auth: auth,
              onSendLikeNotification: onSendLikeNotification,
              onSendCommentNotification: onSendCommentNotification,
            );
          },
          dailyNotificationServiceProvider: DailyNotificationService.new,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(MainPage)) as dynamic;
    state.onItemTapped(1);
    await tester.pump();

    expect(testPage.refreshed.value, isTrue);
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

    final userDoc =
        await fakeFirestore.collection('users').doc(testUser.uid).get();

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

  testWidgets('skips Firestore write and reminder when token unchanged', (
    tester,
  ) async {
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u-skip'),
      signedIn: true,
    );
    final firestore = FakeFirebaseFirestore();
    final messaging = FakeFirebaseMessaging('tok');
    final service = RecordingNotificationService(auth: auth);

    SharedPreferences.setMockInitialValues({'fcmToken': 'tok'});

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          firestore: firestore,
          messaging: messaging,
          dailyNotificationServiceProvider: () => service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.scheduled, isFalse);
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
    final now = DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
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
          sendLikeNotification: (
              {required String ownerUid, required String likerName}) async {
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

  testWidgets('calls sendCommentNotification when a comment is submitted', (
    tester,
  ) async {
    bool wasCalled = false;
    String? calledUid;
    String? calledName;

    final fakeFirestore = FakeFirebaseFirestore();
    final commenter = MockUser(
      uid: 'commenter123',
      displayName: 'Test Commenter',
    );
    final auth = MockFirebaseAuth(mockUser: commenter, signedIn: true);

    // Seed Firestore with an owner log entry
    await fakeFirestore.collection('users').doc('owner456').set({});
    final now = DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
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
          sendCommentNotification: ({
            required String ownerUid,
            required String commenterName,
          }) async {
            wasCalled = true;
            calledUid = ownerUid;
            calledName = commenterName;
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Navigate to Feed (ReadLogPage)
    await tester.tap(find.byIcon(Icons.feed));
    await tester.pumpAndSettle();

    final ownerLogFinder = find.byWidgetPredicate(
      (widget) =>
          widget is ListTile &&
          widget.title is Text &&
          (widget.title as Text).data == 'Owner read today!',
    );
    expect(ownerLogFinder, findsOneWidget);

    // Open comment drawer
    await tester.tap(
      find.descendant(
        of: ownerLogFinder,
        matching: find.byIcon(Icons.mode_comment_outlined),
      ),
    );
    await tester.pumpAndSettle();

    // Submit a comment
    await tester.enterText(find.byType(TextField), 'Nice read');
    await tester.tap(find.byIcon(Icons.send));
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

  testWidgets('ignores navigation when App Check fails', (tester) async {
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

    // Verify the error page is shown.
    expect(find.textContaining('App verification failed'), findsOneWidget);

    // Record the state and attempt to select the Feed destination.
    final state = tester.state(find.byType(MainPage)) as dynamic;
    expect(state.selectedIndex, equals(0));
    state.onItemTapped(1);
    await tester.pump();

    // Navigation should have no effect.
    expect(find.textContaining('App verification failed'), findsOneWidget);
    expect(state.selectedIndex, equals(0));
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
    expect(scaffold.destinations.length, 0);
    expect(find.byIcon(Icons.home), findsNothing);
    expect(find.byIcon(Icons.feed), findsNothing);
    expect(find.byIcon(Icons.leaderboard), findsNothing);
    expect(find.byIcon(Icons.people), findsNothing);

    scaffold.onDestinationSelected(1);
    await tester.pump();

    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('drawer navigation updates content index', (tester) async {
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
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(MainPage)) as dynamic;
    state.navigateFromMenu(4);
    await tester.pumpAndSettle();

    final responsive = tester.widget<ResponsiveScaffold>(
      find.byType(ResponsiveScaffold),
    );
    expect(responsive.selectedIndex, 4);
    expect(responsive.contentIndex, 4);
  });
}
