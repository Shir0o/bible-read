import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/app_notification.dart';
import 'package:bible_read/models/notification_preferences.dart';
import 'package:bible_read/services/notification_service.dart';

class _TrackingFakeFirebaseFirestore extends FakeFirebaseFirestore {
  bool batchRequested = false;

  @override
  WriteBatch batch() {
    batchRequested = true;
    return super.batch();
  }
}

void main() {
  group('NotificationService', () {
    late FakeFirebaseFirestore firestore;
    late NotificationService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = NotificationService(firestore: firestore);
    });

    test('notifications streams ordered notifications', () async {
      final uid = 'user1';
      final collection = firestore
          .collection(NotificationCollections.users)
          .doc(uid)
          .collection(NotificationCollections.notifications);

      await collection.doc('n1').set({
        'type': NotificationType.like.name,
        'timestamp': Timestamp.fromMillisecondsSinceEpoch(1),
        'read': false,
        'senderUid': 'a',
      });
      await collection.doc('n2').set({
        'type': NotificationType.nudge.name,
        'timestamp': Timestamp.fromMillisecondsSinceEpoch(2),
        'read': true,
        'senderUid': 'b',
      });

      final list = await service.notifications(uid).first;
      expect(list.length, 2);
      expect(list.first.id, 'n2');
      expect(list.last.id, 'n1');
    });

    test('markRead updates document', () async {
      final uid = 'user1';
      final collection = firestore
          .collection(NotificationCollections.users)
          .doc(uid)
          .collection(NotificationCollections.notifications);

      await collection.doc('n1').set({
        'type': NotificationType.like.name,
        'timestamp': Timestamp.now(),
        'read': false,
      });

      await service.markRead(uid, 'n1');

      final doc = await collection.doc('n1').get();
      expect(doc.data()?['read'], true);
    });

    test('addNotification writes notification', () async {
      final uid = 'user1';
      final n = AppNotification(
        id: 'n1',
        type: NotificationType.signup,
        fromUid: 'u2',
        senderUid: 'u2',
        message: 'hello',
        timestamp: DateTime.now(),
        read: false,
      );

      await service.addNotification(uid, n);

      final doc = await firestore
          .collection(NotificationCollections.users)
          .doc(uid)
          .collection(NotificationCollections.notifications)
          .doc('n1')
          .get();
      expect(doc.exists, isTrue);
      final stored = AppNotification.fromFirestore(doc.id, doc.data()!);
      expect(stored.type, n.type);
      expect(stored.fromUid, n.fromUid);
      expect(stored.message, n.message);
      expect(stored.read, n.read);
    });

    test('clearNotifications deletes all notifications', () async {
      final uid = 'user1';
      final collection = firestore
          .collection(NotificationCollections.users)
          .doc(uid)
          .collection(NotificationCollections.notifications);

      await collection.doc('n1').set({
        'type': NotificationType.like.name,
        'timestamp': Timestamp.fromMillisecondsSinceEpoch(1),
      });
      await collection.doc('n2').set({
        'type': NotificationType.nudge.name,
        'timestamp': Timestamp.fromMillisecondsSinceEpoch(2),
      });

      await service.clearNotifications(uid);

      final snapshot = await collection.get();
      expect(snapshot.docs, isEmpty);
    });

    test('clearNotifications returns early when nothing to delete', () async {
      final trackingFirestore = _TrackingFakeFirebaseFirestore();
      final trackingService = NotificationService(firestore: trackingFirestore);

      await trackingService.clearNotifications('empty-user');

      expect(trackingFirestore.batchRequested, isFalse);
    });
  });
}
