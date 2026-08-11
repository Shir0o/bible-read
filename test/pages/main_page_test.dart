// ignore_for_file: depend_on_referenced_packages
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import '../helpers/fake_google_sign_in_platform.dart';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/welcome_page.dart';

import 'package:bible_read/pages/friends_page.dart';
import 'package:bible_read/widgets/responsive_scaffold.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_read/services/vibration_service.dart';

import '../helpers/test_read_log_page.dart';
import 'dart:io';
import 'dart:async';

class MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return MockHttpClient();
  }
}

class MockHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return MockHttpClientRequest();
  }
}

class MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async {
    return MockHttpClientResponse();
  }
}

class MockHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  int get contentLength => 67;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    // 1x1 transparent pixel png
    final List<int> bytes = [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ];
    return Stream<List<int>>.value(bytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
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
  HttpOverrides.global = MockHttpOverrides();
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
          auth: MockFirebaseAuth(signedIn: false),
          firestore: FakeFirebaseFirestore(),
          messaging: FakeFirebaseMessaging(null),
          vibrationService: _RecordingVibrationService(),
        ),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));

    // Profile should be shown by default when not authenticated
    // NOW IT SHOWS WELCOME PAGE FIRST
    // We expect WelcomePage, then tap "Get Started", then see "Sign in with Google"

    // 1. Verify Welcome Page is shown (checking for Get Started button text)
    expect(find.text('Get Started'), findsOneWidget);

    // 2. Tap Get Started
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    // 3. Now verify AuthSelectionPage is shown
    expect(find.text('Continue with Google'), findsOneWidget);

    // Profile should be shown when tapping profile or if it's the only page.
    if (find.byIcon(Icons.person).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.person));
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('tapping protected drawer item when signed out has no effect', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final auth = MockFirebaseAuth(signedIn: false);
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          vibrationService: _RecordingVibrationService(),
        ),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));

    // Attempt to navigate to a protected page via the menu API.
    final state =
        tester.state(find.byType(MainPage, skipOffstage: false)) as dynamic;
    state.navigateFromMenu(4); // Friends index.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // The profile page should remain visible and navigation index unchanged (default Home=0).
    expect(state.selectedIndex, 0);
    expect(find.text('Get Started'), findsOneWidget);
  });

  testWidgets('navigation updates selected index', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
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
            vibrationService: _RecordingVibrationService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (find.bySemanticsLabel('Dismiss check-in').evaluate().isNotEmpty) {
      await tester.tap(find.bySemanticsLabel('Dismiss check-in'));
      await tester.pumpAndSettle();
    }
    expect(find.byType(ResponsiveScaffold), findsOneWidget);
    var responsive = tester.widget<ResponsiveScaffold>(
      find.byType(ResponsiveScaffold),
    );
    expect(responsive.contentIndex, 0);
    final labels = responsive.destinations.map((d) => d.label).toList();
    expect(labels, ['Home', 'Community', 'Journey']);
    expect(responsive.selectedIndex, 0);

    // Tap Feed (Community, index 1)
    await tester.tap(find.byIcon(Icons.people_outlined));
    await tester.pumpAndSettle();
    // CommunityPage is shown directly
    expect(find.text('No active groups'), findsOneWidget);
    responsive = tester.widget<ResponsiveScaffold>(
      find.byType(ResponsiveScaffold),
    );
    expect(responsive.contentIndex, 1);
    expect(responsive.selectedIndex, 1);

    // Return home before opening menu destinations
    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    responsive = tester.widget<ResponsiveScaffold>(
      find.byType(ResponsiveScaffold),
    );
    expect(responsive.contentIndex, 0);
    expect(responsive.selectedIndex, 0);

    Future<void> selectMenuItem(
      String label,
      int expectedIndex, {
      String? expectedTitle,
    }) async {
      final state =
          tester.state(find.byType(MainPage, skipOffstage: false)) as dynamic;
      state.navigateFromMenu(expectedIndex);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      if (expectedIndex >= 3 && expectedIndex != 10) {
        Navigator.pop(state.context);
        await tester.pumpAndSettle();
      }

      if (expectedIndex != 10) {
        responsive = tester.widget<ResponsiveScaffold>(
          find.byType(ResponsiveScaffold),
        );
        expect(responsive.contentIndex, 0);
        expect(responsive.selectedIndex, 0);
      } else {
        await tester.pumpAndSettle();
        expect(find.byType(WelcomePage), findsOneWidget);
      }
    }

    // These usages are now checking no-op behavior for pushed items
    await selectMenuItem('Challenges', 5); // 5 is pushed
    await selectMenuItem('Friends', 4);
    await selectMenuItem('Sign Out', 10);
  });

  testWidgets('bottom navigation visible on non-core pages', (tester) async {
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
          vibrationService: _RecordingVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (find.bySemanticsLabel('Dismiss check-in').evaluate().isNotEmpty) {
      await tester.tap(find.bySemanticsLabel('Dismiss check-in'));
      await tester.pumpAndSettle();
    }

    final hasNav = find.byType(NavigationBar).evaluate().isNotEmpty ||
        find.byType(NavigationRail).evaluate().isNotEmpty;
    expect(hasNav, isTrue);

    final state =
        tester.state(find.byType(MainPage, skipOffstage: false)) as dynamic;
    state.navigateFromMenu(4);
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(FriendsPage), findsOneWidget);

    final hasNavAfter = find
            .byType(NavigationBar, skipOffstage: false)
            .evaluate()
            .isNotEmpty ||
        find.byType(NavigationRail, skipOffstage: false).evaluate().isNotEmpty;
    expect(hasNavAfter, isTrue);
  });

  testWidgets('_navigateFromMenu triggers vibration before updating index', (
    tester,
  ) async {
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
        ),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));

    final state =
        tester.state(find.byType(MainPage, skipOffstage: false)) as dynamic;
    vibration.getIndex = () => state.selectedIndex;

    state.navigateFromMenu(4);
    await tester.pump();

    expect(vibration.lightCount, 1);
    expect(vibration.indexDuringCall, 0); // Starting index is 0
    expect(state.selectedIndex, 0); // Stays 0 as Friends is a pushed page
  });

  testWidgets('_navigateFromMenu does not vibrate when navigation blocked', (
    tester,
  ) async {
    final auth = MockFirebaseAuth();
    final vibration = _RecordingVibrationService();
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          firestore: FakeFirebaseFirestore(),
          vibrationService: vibration,
          messaging: FakeFirebaseMessaging(null),
        ),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));

    final state =
        tester.state(find.byType(MainPage, skipOffstage: false)) as dynamic;
    state.navigateFromMenu(4);
    await tester.pump();

    expect(vibration.lightCount, 0);
    expect(state.selectedIndex, 0); // Blocked by auth, stays at 0
  });

  testWidgets('_onItemTapped exits without vibration when blocked', (
    tester,
  ) async {
    final vibration = _RecordingVibrationService();
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          appCheckFailed: true,
          firestore: FakeFirebaseFirestore(),
          auth: MockFirebaseAuth(),
          vibrationService: vibration,
          messaging: FakeFirebaseMessaging(null),
        ),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));

    final state =
        tester.state(find.byType(MainPage, skipOffstage: false)) as dynamic;
    vibration.getIndex = () => state.selectedIndex;

    state.onItemTapped(1);
    await tester.pump();

    expect(vibration.lightCount, 0);
    expect(state.selectedIndex, 0); // Should remain 0 as navigation is blocked
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
          vibrationService: _RecordingVibrationService(),
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
        ),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));

    final state =
        tester.state(find.byType(MainPage, skipOffstage: false)) as dynamic;
    state.onItemTapped(1);
    await tester.pumpAndSettle();

    // CommunityPage defaults to Groups tab (index 0). Switch to Feed (index 1) to build ReadLogPage.
    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();

    expect(testPage.refreshed.value, isTrue);
  }, skip: true);

  /*
  testWidgets('attemptSilentSignIn runs during initState', (tester) async {
    fakePlatform.user = GoogleSignInUserData(
      email: 'test@example.com',
      id: '123',
      displayName: 'Test',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          vibrationService: _RecordingVibrationService(),
        ),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));
    expect(fakePlatform.silentSignInCount, 1);
  });
  */

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
            vibrationService: _RecordingVibrationService(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(400, 600)),
          child: MainPage(
            auth: auth,
            vibrationService: _RecordingVibrationService(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
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
            vibrationService: _RecordingVibrationService(),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(NavigationDestination), findsNothing);
    expect(find.text('Get Started'), findsOneWidget);

    // ResponsiveScaffold is not present when unauthenticated (UserProfilePage is shown)
    expect(find.byType(ResponsiveScaffold), findsNothing);

    // Attempt navigation via MainPage method directly if exposed, or rely on UI not having nav
    final state =
        tester.state(find.byType(MainPage, skipOffstage: false)) as dynamic;
    state.onItemTapped(1);
    await tester.pump();

    expect(find.text('Get Started'), findsOneWidget);
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
          vibrationService: _RecordingVibrationService(),
        ),
      ),
    );

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));

    final userDoc =
        await fakeFirestore.collection('users').doc(testUser.uid).get();

    expect(userDoc.exists, isTrue);
    expect(userDoc.data()!.containsKey('fcmToken'), isTrue);
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

    // Make 'owner456' a friend of 'liker123' so their activity shows up
    await fakeFirestore
        .collection('users')
        .doc(testUser.uid)
        .collection('friends')
        .doc('owner456')
        .set({'name': 'Owner User'});

    // Add a read log entry for 'owner456'
    final now = DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Ensure parent doc exists for FakeFirestore
    await fakeFirestore.collection('read_logs').doc(dateKey).set({});

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
          vibrationService: _RecordingVibrationService(),
          sendLikeNotification: (
              {required String ownerUid, required String likerName}) async {
            wasCalled = true;
            calledUid = ownerUid;
            calledName = likerName;
          },
        ),
      ),
    );

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));

    // Navigate to Community
    await tester.tap(find.byIcon(Icons.people_outlined));
    await tester.pumpAndSettle();

    // Wait for logs to load
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Verify loading is done
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Check if empty state is shown (debug)
    if (find.text('No recent activity from friends.').evaluate().isNotEmpty) {
      fail('Friends activity list is empty, expected "Owner"');
    }

    // Verify 'Owner' is visible (ReadLog splits name to first name)
    // Note: It's in a RichText "Owner read today".
    // "O" is found in avatar.
    expect(find.text('O'), findsOneWidget);
    // Expect like button
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    // Tap like button (heart icon)
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));

    expect(wasCalled, isTrue);
    expect(calledUid, 'owner456');
    expect(calledName, 'Test');
    // Skipped: the Friends Activity feed (and its like button) was removed from
    // Community in the "Circle" redesign.
  }, skip: true);

  testWidgets('calls sendCommentNotification when a comment is submitted', (
    tester,
  ) async {
    final fakeFirestore = FakeFirebaseFirestore();
    final commenter = MockUser(
      uid: 'commenter123',
      displayName: 'Test Commenter',
    );
    final auth = MockFirebaseAuth(mockUser: commenter, signedIn: true);

    // Seed Firestore with an owner log entry
    await fakeFirestore.collection('users').doc('owner456').set({});

    // Make 'owner456' a friend of 'commenter123'
    await fakeFirestore
        .collection('users')
        .doc(commenter.uid)
        .collection('friends')
        .doc('owner456')
        .set({'name': 'Owner User'});

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
          vibrationService: _RecordingVibrationService(),
          sendCommentNotification: ({
            required String ownerUid,
            required String commenterName,
          }) async {
            // No-op
          },
        ),
      ),
    );

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));

    // Navigate to Community
    await tester.tap(find.byIcon(Icons.people_outlined));
    await tester.pumpAndSettle();

    // Wait for logs to load
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Verify 'Owner' is visible
    expect(find.text('Owner'), findsOneWidget);

    // New design doesn't support adding comments from the list directly
  }, skip: true);

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
          vibrationService: _RecordingVibrationService(),
        ),
      ),
    );

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));

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
          vibrationService: _RecordingVibrationService(),
        ),
      ),
    );

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));

    // Verify the error page is shown.
    expect(find.textContaining('App verification failed'), findsOneWidget);

    // Record the state and attempt to select the Feed destination.
    final state =
        tester.state(find.byType(MainPage, skipOffstage: false)) as dynamic;
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
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    fakePlatform.user = GoogleSignInUserData(
      email: 'test@example.com',
      id: '123',
      displayName: 'Test',
    );
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          firestore: firestore,
          messaging: FakeFirebaseMessaging(null),
          vibrationService: _RecordingVibrationService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    if (find.bySemanticsLabel('Dismiss check-in').evaluate().isNotEmpty) {
      await tester.tap(find.bySemanticsLabel('Dismiss check-in'));
      await tester.pumpAndSettle();
    }

    final state =
        tester.state(find.byType(MainPage, skipOffstage: false)) as dynamic;

    // Navigate to a different page first
    await tester.tap(find.byIcon(Icons.people_outlined));
    await tester.pumpAndSettle();
    expect(find.text('No active groups'), findsOneWidget);

    // Go to profile through the menu and sign out
    state.navigateFromMenu(10);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Should now show the unauthenticated profile page
    expect(find.text('Get Started'), findsOneWidget);

    expect(find.byType(ResponsiveScaffold), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);

    state.onItemTapped(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Attempt to use the menu to go elsewhere should be blocked
    state.navigateFromMenu(4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Get Started'), findsOneWidget);
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
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          firestore: firestore,
          messaging: FakeFirebaseMessaging(null),
          vibrationService: _RecordingVibrationService(),
        ),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));

    final state =
        tester.state(find.byType(MainPage, skipOffstage: false)) as dynamic;
    state.navigateFromMenu(5);
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));

    final responsive = tester.widget<ResponsiveScaffold>(
      find.byType(ResponsiveScaffold),
    );
    // Menu navigation is handled by pushing routes, so MainPage index remains unchanged (0).
    expect(responsive.selectedIndex, 0);
    expect(responsive.contentIndex, 0);
  }, skip: true);
}
