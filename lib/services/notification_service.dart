import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';

/// Firestore collection names used by [NotificationService].
class NotificationCollections {
  NotificationCollections._();

  /// Top-level users collection.
  static const String users = 'users';

  /// Sub-collection containing notifications for a user.
  static const String notifications = 'notifications';
}

/// Service for reading and updating user notifications.
class NotificationService {
  /// Firestore instance used for database operations.
  final FirebaseFirestore firestore;

  /// Creates a [NotificationService] using [FirebaseFirestore.instance] by default.
  NotificationService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  /// Stream of notifications for [uid] ordered by timestamp descending.
  Stream<List<AppNotification>> notifications(String uid) {
    return firestore
        .collection(NotificationCollections.users)
        .doc(uid)
        .collection(NotificationCollections.notifications)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => AppNotification.fromFirestore(d.id, d.data()))
            .toList());
  }

  /// Marks the notification [notificationId] for [uid] as read.
  Future<void> markRead(String uid, String notificationId) async {
    await firestore
        .collection(NotificationCollections.users)
        .doc(uid)
        .collection(NotificationCollections.notifications)
        .doc(notificationId)
        .set({'read': true}, SetOptions(merge: true));
  }

  /// Adds a notification [n] for user [uid]. Useful for testing.
  Future<void> addNotification(String uid, AppNotification n) async {
    await firestore
        .collection(NotificationCollections.users)
        .doc(uid)
        .collection(NotificationCollections.notifications)
        .doc(n.id)
        .set(n.toFirestore());
  }
}
