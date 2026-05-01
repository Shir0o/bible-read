import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/pages/notification_settings_page.dart';
import 'package:bible_read/services/notification_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('toggling switch updates Firestore', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('users')
        .doc('u1')
        .collection('notificationPrefs')
        .doc('like')
        .set({'enabled': false});
    await firestore
        .collection('users')
        .doc('u1')
        .collection('notificationPrefs')
        .doc('vibration')
        .set({'enabled': false});

    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    final service = NotificationPreferencesService(firestore: firestore);

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationSettingsPage(service: service, auth: auth),
      ),
    );
    await tester.pumpAndSettle();

    const labels = [
      'Like Notifications',
      'Nudge Notifications',
      'Signup Alerts',
      'Friend Request Notifications',
      'Comment Notifications',
      'Group Join Request Notifications',
      'Group Schedule Update Notifications',
      'Group Invite Notifications',
      'Seasonal Challenge Notifications',
      'Vibration',
    ];
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }

    final likeSwitch = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Like Notifications'));
    expect(likeSwitch.value, isFalse);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Like Notifications'));
    await tester.pumpAndSettle();

    final doc = await firestore
        .collection('users')
        .doc('u1')
        .collection('notificationPrefs')
        .doc('like')
        .get();
    expect(doc.data()?['enabled'], true);

    final vibrationSwitch = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Vibration'));
    expect(vibrationSwitch.value, isFalse);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Vibration'));
    await tester.pumpAndSettle();

    final vibrationDoc = await firestore
        .collection('users')
        .doc('u1')
        .collection('notificationPrefs')
        .doc('vibration')
        .get();
    expect(vibrationDoc.data()?['enabled'], true);
  });
}
