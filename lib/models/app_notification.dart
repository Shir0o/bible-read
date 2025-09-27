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

  /// UID of the sender of the notification.
  final String? senderUid;

  /// Optional message content.
  final String? message;

  /// Optional group id this notification refers to (e.g., group join request).
  final String? groupId;

  /// Time the notification was created.
  final DateTime timestamp;

  /// Whether the notification has been read.
  final bool read;

  /// Creates an [AppNotification].
  const AppNotification({
    required this.id,
    required this.type,
    this.fromUid,
    this.senderUid,
    this.message,
    this.groupId,
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
      senderUid: data['senderUid'] as String?,
      message: data['message'] as String?,
      groupId: data['groupId'] as String?,
      timestamp: ts is Timestamp ? ts.toDate() : DateTime.now(),
      read: data['read'] is bool ? data['read'] as bool : false,
    );
  }

  /// Serializes this notification for Firestore.
  Map<String, dynamic> toFirestore() => {
        'type': type.name,
        if (fromUid != null) 'fromUid': fromUid,
        if (senderUid != null) 'senderUid': senderUid,
        if (message != null) 'message': message,
        if (groupId != null) 'groupId': groupId,
        'timestamp': Timestamp.fromDate(timestamp),
        'read': read,
      };
}
