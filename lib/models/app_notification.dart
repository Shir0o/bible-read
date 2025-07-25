import 'package:cloud_firestore/cloud_firestore.dart';

import 'notification_preferences.dart';

/// Represents a stored notification for a user.
class AppNotification {
  /// Document id for this notification.
  final String id;

  /// Type of notification.
  final NotificationType type;

  /// UID of the user that triggered the notification, if any.
  final String? fromUid;

  /// Optional message content.
  final String? message;

  /// Time the notification was created.
  final DateTime timestamp;

  /// Whether the notification has been read.
  final bool read;

  /// Creates an [AppNotification].
  const AppNotification({
    required this.id,
    required this.type,
    this.fromUid,
    this.message,
    required this.timestamp,
    required this.read,
  });

  /// Reads an [AppNotification] from Firestore data.
  factory AppNotification.fromFirestore(String id, Map<String, dynamic> data) {
    final typeName = data['type'] as String?;
    final type = NotificationType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => NotificationType.like,
    );
    final ts = data['timestamp'];
    return AppNotification(
      id: id,
      type: type,
      fromUid: data['fromUid'] as String?,
      message: data['message'] as String?,
      timestamp: ts is Timestamp ? ts.toDate() : DateTime.now(),
      read: data['read'] is bool ? data['read'] as bool : false,
    );
  }

  /// Serializes this notification for Firestore.
  Map<String, dynamic> toFirestore() => {
        'type': type.name,
        if (fromUid != null) 'fromUid': fromUid,
        if (message != null) 'message': message,
        'timestamp': Timestamp.fromDate(timestamp),
        'read': read,
      };
}
