/// Represents general user preferences for the application.
class UserPreferences {
  /// Whether to automatically mark today's reading in a personal plan
  /// when the user marks their daily reading as complete.
  final bool autoMarkPlanRead;

  /// Creates a [UserPreferences] instance.
  const UserPreferences({
    this.autoMarkPlanRead = false,
  });

  /// Reads preferences from Firestore data.
  factory UserPreferences.fromFirestore(Map<String, dynamic>? data) {
    return UserPreferences(
      autoMarkPlanRead: data?['autoMarkPlanRead'] as bool? ?? false,
    );
  }

  /// Serializes preferences for Firestore.
  Map<String, dynamic> toFirestore() => {
        'autoMarkPlanRead': autoMarkPlanRead,
      };

  /// Creates a copy of this preferences object with the given fields replaced.
  UserPreferences copyWith({
    bool? autoMarkPlanRead,
  }) {
    return UserPreferences(
      autoMarkPlanRead: autoMarkPlanRead ?? this.autoMarkPlanRead,
    );
  }
}
