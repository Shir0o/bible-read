// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../helpers/fake_google_sign_in_platform.dart';

import 'package:bible_read/pages/main_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:bible_read/pages/user_profile_page.dart';
import 'package:bible_read/widgets/badge_icon.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrackingAuth extends MockFirebaseAuth {
  TrackingAuth()
      : super(
          mockUser: MockUser(photoURL: ''),
        );

  bool signInCalled = false;
  bool signOutCalled = false;
  AuthCredential? receivedCredential;

  @override
  Future<UserCredential> signInWithCredential(AuthCredential? credential) {
    signInCalled = true;
    receivedCredential = credential;
    return super.signInWithCredential(credential);
  }

  @override
  Future<void> signOut() {
    signOutCalled = true;
    return super.signOut();
  }
}

class _RecordingVibrationService extends VibrationService {
  int lightCount = 0;

  @override
  Future<void> lightImpact() async {
    lightCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows loading then auth options', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UserProfilePage(),
      ),
    );

    // Initially loading indicator
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Email Sign In'), findsOneWidget);
    expect(find.text('Email Sign Up'), findsOneWidget);
  });

  testWidgets('email sign-in button vibrates', (tester) async {
    await mockNetworkImagesFor(() async {
      final vibration = _RecordingVibrationService();
      await tester.pumpWidget(
        MaterialApp(
          home: UserProfilePage(
            auth: MockFirebaseAuth(),
            firestore: FakeFirebaseFirestore(),
            vibrationService: vibration,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Email Sign In'));
      await tester.pumpAndSettle();
      expect(vibration.lightCount, 1);
    });
  });

  testWidgets('email sign-up button vibrates', (tester) async {
    await mockNetworkImagesFor(() async {
      final vibration = _RecordingVibrationService();
      await tester.pumpWidget(
        MaterialApp(
          home: UserProfilePage(
            auth: MockFirebaseAuth(),
            firestore: FakeFirebaseFirestore(),
            vibrationService: vibration,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Email Sign Up'));
      await tester.pumpAndSettle();
      expect(vibration.lightCount, 1);
    });
  });

  testWidgets('successful sign in navigates to main page', (tester) async {
    await mockNetworkImagesFor(() async {
      final googlePlatform = FakeGoogleSignInPlatform(
        user: GoogleSignInUserData(email: 'e', id: 'id', displayName: 'd'),
      );
      GoogleSignInPlatform.instance = googlePlatform;
      final auth = TrackingAuth();

      await tester.pumpWidget(
        MaterialApp(
          home: UserProfilePage(
            auth: auth,
            mainPageBuilder: (_) => MainPage(
              auth: auth,
              firestore: FakeFirebaseFirestore(),
              messaging: FakeFirebaseMessaging(null),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign in with Google'));
      await tester.pumpAndSettle();

      expect(googlePlatform.signInCalled, isTrue);
      expect(auth.signInCalled, isTrue);
      expect(find.byType(MainPage), findsOneWidget);
    });
  });

  testWidgets('sign in cancelled shows snackbar', (tester) async {
    final googlePlatform = FakeGoogleSignInPlatform(user: null);
    GoogleSignInPlatform.instance = googlePlatform;
    final auth = TrackingAuth();

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfilePage(
          auth: auth,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with Google'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Sign in cancelled'), findsOneWidget);
    expect(auth.signInCalled, isFalse);
  });

  testWidgets('sign in failure shows snackbar', (tester) async {
    final googlePlatform =
        FakeGoogleSignInPlatform(signInError: Exception('fail'));
    GoogleSignInPlatform.instance = googlePlatform;
    final auth = TrackingAuth();

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfilePage(
          auth: auth,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with Google'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(auth.signInCalled, isFalse);

    await tester.pumpAndSettle();
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('shows user info when user provided', (tester) async {
    await mockNetworkImagesFor(() async {
      final userData = GoogleSignInUserData(
        email: 'test@example.com',
        id: 'id',
        displayName: 'Test User',
      );
      final googlePlatform = FakeGoogleSignInPlatform(
        user: userData,
      );
      GoogleSignInPlatform.instance = googlePlatform;

      final account = await GoogleSignIn.instance.authenticate();

      await tester.pumpWidget(
        MaterialApp(
          home: UserProfilePage(
            user: account,
          ),
        ),
      );

      // Loading indicator shown first
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.text('Test User'), findsOneWidget);
      expect(find.text('test@example.com'), findsOneWidget);
      expect(find.text('Sign in with Google'), findsNothing);
    });
  });

  testWidgets('shows firebase user info when no google user provided',
      (tester) async {
    await mockNetworkImagesFor(() async {
      final auth = MockFirebaseAuth(
        mockUser: MockUser(
          uid: 'abc',
          email: 'firebase@example.com',
          displayName: 'Firebase User',
          photoURL: '',
        ),
        signedIn: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: UserProfilePage(
            auth: auth,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Firebase User'), findsOneWidget);
      expect(find.text('firebase@example.com'), findsOneWidget);
      expect(find.text('Sign in with Google'), findsNothing);
    });
  });

  testWidgets('sign out signs out google and firebase', (tester) async {
    await mockNetworkImagesFor(() async {
      final googlePlatform = FakeGoogleSignInPlatform(
        user: GoogleSignInUserData(
          email: 'signout@example.com',
          id: 'id',
          displayName: 'Sign Out User',
        ),
      );
      GoogleSignInPlatform.instance = googlePlatform;
      final auth = TrackingAuth();

      final account = await GoogleSignIn.instance.authenticate();

      await tester.pumpWidget(
        MaterialApp(
          home: UserProfilePage(
            user: account,
            auth: auth,
            mainPageBuilder: (_) => MainPage(
              auth: auth,
              firestore: FakeFirebaseFirestore(),
              messaging: FakeFirebaseMessaging(null),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();

      expect(googlePlatform.signOutCalled, isTrue);
      expect(auth.signOutCalled, isTrue);
    });
  });

  testWidgets('notification settings button vibrates', (tester) async {
    await mockNetworkImagesFor(() async {
      final vibration = _RecordingVibrationService();
      final firestore = FakeFirebaseFirestore();
      final auth =
          MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);

      await tester.pumpWidget(
        MaterialApp(
          home: UserProfilePage(
            auth: auth,
            firestore: firestore,
            vibrationService: vibration,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Notification Settings'));
      await tester.pumpAndSettle();

      expect(vibration.lightCount, 1);
    });
  });

  testWidgets('shows achievements summary for signed in user', (tester) async {
    await mockNetworkImagesFor(() async {
      final firestore = FakeFirebaseFirestore();
      final user = MockUser(uid: 'u1');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('achievements')
          .doc('a1')
          .set({
        'title': 'Test',
        'type': 't',
        'dateUnlocked': Timestamp.fromDate(DateTime(2025)),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: UserProfilePage(
            auth: auth,
            firestore: firestore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BadgeIcon), findsOneWidget);
    });
  });
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
