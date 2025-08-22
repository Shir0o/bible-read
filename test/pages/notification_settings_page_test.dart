import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/models/notification_preferences.dart';
import 'package:bible_read/pages/notification_settings_page.dart';
import 'package:bible_read/services/notification_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('toggling switch updates Firestore', (tester) async {
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

    expect(find.byType(SwitchListTile),
        findsNWidgets(NotificationType.values.length + 1));
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

    // Daily reminder switch defaults to true. Toggle it off and verify
    // Firestore updates accordingly.
    final dailySwitch = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Daily Reading Reminder'));
    expect(dailySwitch.value, isTrue);

    await tester
        .tap(find.widgetWithText(SwitchListTile, 'Daily Reading Reminder'));
    await tester.pumpAndSettle();

    final dailyDoc = await firestore
        .collection('users')
        .doc('u1')
        .collection('notificationPrefs')
        .doc('dailyReminder')
        .get();
    expect(dailyDoc.data()?['enabled'], false);

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
