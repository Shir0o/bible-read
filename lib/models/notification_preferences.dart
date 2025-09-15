enum NotificationType {
  like,
  nudge,
  signup,
  achievement,
  friendRequest,
  comment,
  groupJoinRequest,
  groupScheduleUpdate,
}

/// Stores whether each notification type is enabled for a user.
class NotificationPreferences {
  /// Map of preferences keyed by [NotificationType].
  final Map<NotificationType, bool> values;

  /// Creates [NotificationPreferences] with the provided [values]. Missing types
  /// default to `true`.
  NotificationPreferences({Map<NotificationType, bool>? values})
      : values = {
          for (final type in NotificationType.values)
            type: values?[type] ?? true,
        };

  /// Reads preferences from Firestore data.
  factory NotificationPreferences.fromFirestore(Map<String, dynamic>? data) {
    return NotificationPreferences(
      values: {
        for (final type in NotificationType.values)
          type: data?[type.name] is bool ? data![type.name] as bool : true,
      },
    );
  }

  /// Serializes preferences for Firestore.
  Map<String, dynamic> toFirestore() => {
        for (final entry in values.entries) entry.key.name: entry.value,
      };

  /// Returns whether [type] is enabled.
  bool operator [](NotificationType type) => values[type] ?? true;
}
