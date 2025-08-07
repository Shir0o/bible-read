import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/app_notification.dart';
import 'package:bible_read/models/notification_preferences.dart';

void main() {
  group('AppNotification', () {
    test('fromFirestore parses data', () {
      final date = DateTime(2024, 1, 1);
      final notif = AppNotification.fromFirestore('n1', {
        'type': 'comment',
        'fromUid': 'u1',
        'senderUid': 'u2',
        'message': 'hi',
        'timestamp': Timestamp.fromDate(date),
        'read': true,
      });
      expect(notif.id, 'n1');
      expect(notif.type, NotificationType.comment);
      expect(notif.fromUid, 'u1');
      expect(notif.senderUid, 'u2');
      expect(notif.message, 'hi');
      expect(notif.timestamp.toUtc(), date.toUtc());
      expect(notif.read, isTrue);
    });

    test('fromFirestore handles malformed fields', () {
      final notif = AppNotification.fromFirestore('n1', {
        'type': 'unknown',
        'timestamp': 'bad',
        'read': 'no',
      });
      expect(notif.type, NotificationType.like);
      expect(notif.fromUid, isNull);
      expect(notif.senderUid, isNull);
      expect(notif.message, isNull);
      expect(notif.read, isFalse);
      expect(notif.timestamp, isA<DateTime>());
    });

    test('toFirestore outputs expected map', () {
      final date = DateTime(2024, 1, 1);
      final notif = AppNotification(
        id: 'n1',
        type: NotificationType.comment,
        fromUid: 'u1',
        senderUid: 'u2',
        message: 'hi',
        timestamp: date,
        read: true,
      );
      final map = notif.toFirestore();
      expect(map, {
        'type': 'comment',
        'fromUid': 'u1',
        'senderUid': 'u2',
        'message': 'hi',
        'timestamp': Timestamp.fromDate(date),
        'read': true,
      });
    });

    test('toFirestore omits null fields', () {
      final date = DateTime(2024, 1, 1);
      final notif = AppNotification(
        id: 'n1',
        type: NotificationType.like,
        timestamp: date,
        read: false,
      );
      final map = notif.toFirestore();
      expect(map, {
        'type': 'like',
        'timestamp': Timestamp.fromDate(date),
        'read': false,
      });
    });
  });
}
