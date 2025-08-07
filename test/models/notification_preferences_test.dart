import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/notification_preferences.dart';

void main() {
  group('NotificationPreferences', () {
    test('fromFirestore handles missing or invalid fields', () {
      final prefs = NotificationPreferences.fromFirestore({'like': 'yes'});
      for (final type in NotificationType.values) {
        expect(prefs[type], isTrue);
      }
    });

    test('fromFirestore reads provided values', () {
      final prefs = NotificationPreferences.fromFirestore({
        'like': false,
        'comment': true,
      });
      expect(prefs[NotificationType.like], isFalse);
      expect(prefs[NotificationType.comment], isTrue);
    });

    test('toFirestore outputs expected map', () {
      final prefs = NotificationPreferences(values: {
        NotificationType.like: false,
        NotificationType.comment: true,
      });
      final map = prefs.toFirestore();
      expect(map['like'], isFalse);
      expect(map['comment'], isTrue);
      expect(map.length, NotificationType.values.length);
    });
  });
}
