enum NotificationType {
  like,
  nudge,
  signup,
  friendRequest,
  comment,
  groupJoinRequest,
  groupScheduleUpdate,
  groupInvite,
  seasonalChallenge,
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
            type: (values ?? {})[type] ?? true,
        };

  /// Returns whether notifications of [type] are enabled.
  bool operator [](NotificationType type) => values[type] ?? true;

  /// Creates [NotificationPreferences] from a Firestore map.
  factory NotificationPreferences.fromFirestore(Map<String, dynamic> data) {
    final values = <NotificationType, bool>{};
    for (final type in NotificationType.values) {
      if (data.containsKey(type.name)) {
        values[type] = data[type.name] == true;
      }
    }
    return NotificationPreferences(values: values);
  }

  /// Converts preferences to a Firestore-compatible map.
  Map<String, dynamic> toFirestore() {
    return {
      for (final entry in values.entries) entry.key.name: entry.value,
    };
  }
}
