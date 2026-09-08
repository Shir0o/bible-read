import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/notification_preferences.dart';

void main() {
  group('NotificationPreferences', () {
    test('fromFirestore handles missing or invalid fields', () {
      final prefs = NotificationPreferences.fromFirestore({'amen': 'invalid'});
      // If the field is invalid (not a boolean), it should default to true or the default value logic.
      // In fromFirestore implementation: values[type] = data[type.name] == true;
      // So 'invalid' == true is false.
      expect(prefs[NotificationType.amen], isFalse);

      // Missing fields should be true
      expect(prefs[NotificationType.groupInvite], isTrue);
    });

    test('fromFirestore reads provided values', () {
      final prefs = NotificationPreferences.fromFirestore({
        'amen': false,
        'nudge': true,
      });
      expect(prefs[NotificationType.amen], isFalse);
      expect(prefs[NotificationType.nudge], isTrue);
    });

    test('toFirestore outputs expected map', () {
      final prefs = NotificationPreferences(
        values: {NotificationType.amen: false, NotificationType.nudge: true},
      );
      final map = prefs.toFirestore();
      expect(map['amen'], isFalse);
      expect(map['nudge'], isTrue);
      expect(map.length, NotificationType.values.length);
    });
  });
}
