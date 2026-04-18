import 'dart:async';
import 'package:bible_read/main.dart' as app;
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/friend_requests_page.dart';
import 'package:bible_read/pages/group_join_requests_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('Deep Link & Notification Navigation Journey', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'alice_uid',
        displayName: 'Alice',
        email: 'alice@example.com',
      ),
      signedIn: true,
    );
    final messaging = FakeFirebaseMessaging();

    // Setup Alice document
    await firestore.collection('users').doc('alice_uid').set({
      'name': 'Alice',
      'email': 'alice@example.com',
    });

    // Override the global notification navigator with our mocks
    app.notificationNavigator = app.NotificationNavigator(
      auth: auth,
      firestore: firestore,
    );
    app.skipMessagingSetup = true;

    // 1. Launch App
    await tester.pumpWidget(app.MyApp(
      appCheckFailed: false,
      firestore: firestore,
      auth: auth,
      messaging: messaging,
    ));
    
    // Wait for auth stream to emit and settle
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Verify app launched
    expect(find.byType(MainPage), findsOneWidget);

    // 2. Simulate Friend Request notification
    // We do NOT await this because it waits for the page to pop!
    unawaited(app.notificationNavigator.navigateForData({
      'type': 'friendRequest',
    }));
    
    // Pump to trigger navigation
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // Verify navigation to FriendRequestsPage
    expect(find.byType(FriendRequestsPage), findsOneWidget);

    // Go back
    final backButton = find.byType(BackButton);
    expect(backButton, findsOneWidget);
    await tester.tap(backButton);
    await tester.pumpAndSettle();

    // 3. Simulate Group Join Request notification
    await firestore.collection('groups').doc('group_1').set({
      'name': 'Test Group',
    });

    unawaited(app.notificationNavigator.navigateForData({
      'type': 'groupJoinRequest',
      'groupId': 'group_1',
    }));
    
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // Verify navigation to GroupJoinRequestsPage
    expect(find.byType(GroupJoinRequestsPage), findsOneWidget);
    expect(find.text('Join Requests'), findsOneWidget);
  });
}

class FakeFirebaseMessaging extends Fake implements FirebaseMessaging {
  @override
  Future<String?> getToken({String? vapidKey}) async => 'fake_token';

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

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
}
