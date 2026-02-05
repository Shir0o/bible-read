import 'package:bible_read/pages/auth_selection_page.dart';
import 'package:bible_read/pages/login_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/user_profile_page.dart';
import 'package:bible_read/pages/welcome_page.dart';
import 'package:bible_read/widgets/responsive_scaffold.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'dart:io';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

// Mocks
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
  Future<bool> isSignedIn() async => user != null;
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

class NoOpVibrationService extends VibrationService {
  @override
  Future<void> lightImpact() async {}
}

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
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
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
      0x82
    ];
    return Stream<List<int>>.value(bytes).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  HttpOverrides.global = MockHttpOverrides();

  setUpAll(() async {
    // Mock Firebase Core
    await Firebase.initializeApp();
  });

  setUp(() {
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();
  });

  testWidgets('Authenticated user sees responsive scaffold with home',
      (tester) async {
    final user = MockUser(uid: 'u1', email: 'test@example.com');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final firestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          firestore: firestore,
          messaging: FakeFirebaseMessaging(null),
          vibrationService: NoOpVibrationService(),
        ),
      ),
    );
    await tester.pump();
    // Wait for StreamBuilder if necessary. MockFirebaseAuth usually emits immediately.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ResponsiveScaffold), findsOneWidget);
    expect(find.byType(UserProfilePage), findsNothing);
    expect(find.text('Home'),
        findsOneWidget); // Assuming Home tab is selected by default
  });

  testWidgets('Unauthenticated user navigation flow', (tester) async {
    final auth = MockFirebaseAuth(signedIn: false);
    final firestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          firestore: firestore,
          messaging: FakeFirebaseMessaging(null),
          vibrationService: NoOpVibrationService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. WelcomePage
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(find.byType(AuthSelectionPage), findsNothing);

    // 2. Tap Get Started
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    // 3. UserProfilePage
    expect(find.byType(WelcomePage), findsNothing);
    expect(find.byType(AuthSelectionPage), findsOneWidget);

    // 4. Back
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 5. WelcomePage again
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(find.byType(AuthSelectionPage), findsNothing);

    // 6. Tap "I already have an account"
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();

    // 7. Verify LoginPage
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(WelcomePage), findsNothing);
  });
}
