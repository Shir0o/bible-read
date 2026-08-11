// ignore_for_file: depend_on_referenced_packages
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_read/pages/check_in_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'helpers/fake_google_sign_in_platform.dart';

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

  setUp(() {
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('back button navigates to previous index', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          firestore: firestore,
          auth: auth,
          messaging: FakeFirebaseMessaging(null),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    if (find.byType(CheckInPage).evaluate().isNotEmpty) {
      tester.widget<CheckInPage>(find.byType(CheckInPage)).onClose();
      await tester.pumpAndSettle();
    }

    final dynamic state = tester.state(find.byType(MainPage));
    state.onItemTapped(1);
    await tester.pumpAndSettle();
    state.onItemTapped(2);
    await tester.pumpAndSettle();

    expect(state.selectedIndex, 2);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(state.selectedIndex, 1);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(state.selectedIndex, 0);
  });
}
