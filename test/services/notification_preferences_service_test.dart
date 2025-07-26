import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/services/notification_preferences_service.dart';
import 'package:bible_read/models/notification_preferences.dart';

void main() {
  group('NotificationPreferencesService', () {
    late FakeFirebaseFirestore firestore;
    late NotificationPreferencesService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = NotificationPreferencesService(firestore: firestore);
    });

    test('fetchPreferences defaults missing types to true', () async {
      final prefs = await service.fetchPreferences('u1');
      for (final t in NotificationType.values) {
        expect(prefs[t], isTrue);
      }
    });

    test(
        'fetchPreferences returns true for dailyReminder when no document exists',
        () async {
      final prefs = await service.fetchPreferences('u1');
      expect(prefs[NotificationType.dailyReminder], isTrue);
    });

    test('updatePreference writes document and updates cache', () async {
      await service.updatePreference(
          'u1', NotificationType.dailyReminder, false);
      final doc = await firestore
          .collection('users')
          .doc('u1')
          .collection('notificationPrefs')
          .doc('dailyReminder')
          .get();
      expect(doc.exists, isTrue);
      expect(doc.data()?['enabled'], false);

      final prefs = await service.fetchPreferences('u1');
      expect(prefs[NotificationType.dailyReminder], isFalse);
    });
  });
}
