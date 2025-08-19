// ignore_for_file: depend_on_referenced_packages
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/widgets/responsive_scaffold.dart';

import '../helpers/test_leaderboard_page.dart';

class FakeGoogleSignInPlatform extends GoogleSignInPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<void> init({
    List<String> scopes = const <String>[],
    SignInOption signInOption = SignInOption.standard,
    String? hostedDomain,
    String? clientId,
  }) async {}

  @override
  Future<GoogleSignInUserData?> signInSilently() async => null;

  @override
  Future<GoogleSignInUserData?> signIn() async => null;

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
  Future<bool> isSignedIn() async => false;

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

  testWidgets('navigating to leaderboard triggers refresh', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);

    late TestLeaderboardPage testPage;

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          firestore: firestore,
          auth: auth,
          messaging: FakeFirebaseMessaging(null),
          leaderboardPageBuilder: ({key, firestore, auth, friendService}) {
            return testPage = TestLeaderboardPage(
              key: key,
              firestore: firestore,
              auth: auth,
              friendService: friendService,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final responsive = tester.widget<ResponsiveScaffold>(
      find.byType(ResponsiveScaffold),
    );
    responsive.scaffoldKey!.currentState!.openDrawer();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Leaderboard'));
    await tester.pumpAndSettle();

    expect(testPage.refreshed.value, isTrue);
  });
}
