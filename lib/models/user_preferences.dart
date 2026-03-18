/// Represents general user preferences for the application.
class UserPreferences {
  /// Whether to automatically mark today's reading in a personal plan
  /// when the user marks their daily reading as complete.
  final bool autoMarkPlanRead;

  /// Whether the user has already seen the prompt about marking plan reading.
  final bool hasSeenPlanPrompt;

  /// Creates a [UserPreferences] instance.
  const UserPreferences({
    this.autoMarkPlanRead = false,
    this.hasSeenPlanPrompt = false,
  });

  /// Reads preferences from Firestore data.
  factory UserPreferences.fromFirestore(Map<String, dynamic>? data) {
    return UserPreferences(
      autoMarkPlanRead: data?['autoMarkPlanRead'] as bool? ?? false,
      hasSeenPlanPrompt: data?['hasSeenPlanPrompt'] as bool? ?? false,
    );
  }

  /// Serializes preferences for Firestore.
  Map<String, dynamic> toFirestore() => {
        'autoMarkPlanRead': autoMarkPlanRead,
        'hasSeenPlanPrompt': hasSeenPlanPrompt,
      };

  /// Creates a copy of this preferences object with the given fields replaced.
  UserPreferences copyWith({
    bool? autoMarkPlanRead,
    bool? hasSeenPlanPrompt,
  }) {
    return UserPreferences(
      autoMarkPlanRead: autoMarkPlanRead ?? this.autoMarkPlanRead,
      hasSeenPlanPrompt: hasSeenPlanPrompt ?? this.hasSeenPlanPrompt,
    );
  }
}
