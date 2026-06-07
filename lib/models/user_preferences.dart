/// Represents general user preferences for the application.
class UserPreferences {
  /// Whether finishing a reading from a plan also counts as "showing up" for
  /// the day (i.e. records the daily habit). The coupling is one-directional:
  /// the bare daily habit tap never advances a plan.
  ///
  /// Persisted under the legacy `autoMarkPlanRead` Firestore key.
  final bool autoMarkPlanRead;

  /// Whether the user has answered the one-time "should finishing a reading
  /// also count as showing up?" prompt. While `false`, the prompt is shown the
  /// first time a plan reading is finished. Together with [autoMarkPlanRead]
  /// this encodes three states: not answered → ask, answered + on → linked,
  /// answered + off → separate.
  final bool syncPromptAnswered;

  /// The reading the user has pinned as "Primary on Home", overriding Home's
  /// automatic ranking of which plan becomes the hero. A typed key:
  /// `"plan:<planId>"` for a personal plan or `"group:<groupId>"` for a group.
  /// `null` means no pin — Home auto-picks the most pressing reading. At most
  /// one reading can be pinned at a time.
  final String? pinnedReadingId;

  /// Creates a [UserPreferences] instance.
  const UserPreferences({
    this.autoMarkPlanRead = false,
    this.syncPromptAnswered = false,
    this.pinnedReadingId,
  });

  /// Reads preferences from Firestore data.
  factory UserPreferences.fromFirestore(Map<String, dynamic>? data) {
    return UserPreferences(
      autoMarkPlanRead: data?['autoMarkPlanRead'] as bool? ?? false,
      syncPromptAnswered: data?['syncPromptAnswered'] as bool? ?? false,
      pinnedReadingId: data?['pinnedReadingId'] as String?,
    );
  }

  /// Serializes preferences for Firestore.
  Map<String, dynamic> toFirestore() => {
        'autoMarkPlanRead': autoMarkPlanRead,
        'syncPromptAnswered': syncPromptAnswered,
        'pinnedReadingId': pinnedReadingId,
      };

  /// Creates a copy of this preferences object with the given fields replaced.
  ///
  /// Pass [clearPinnedReadingId] to reset the pin to `null` (since a `null`
  /// [pinnedReadingId] argument is indistinguishable from "leave unchanged").
  UserPreferences copyWith({
    bool? autoMarkPlanRead,
    bool? syncPromptAnswered,
    String? pinnedReadingId,
    bool clearPinnedReadingId = false,
  }) {
    return UserPreferences(
      autoMarkPlanRead: autoMarkPlanRead ?? this.autoMarkPlanRead,
      syncPromptAnswered: syncPromptAnswered ?? this.syncPromptAnswered,
      pinnedReadingId: clearPinnedReadingId
          ? null
          : (pinnedReadingId ?? this.pinnedReadingId),
    );
  }
}
