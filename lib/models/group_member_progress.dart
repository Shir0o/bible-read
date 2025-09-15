/// Represents the daily reading progress for a group member.
class GroupMemberProgressData {
  /// Unique identifier for the member.
  final String uid;

  /// Display name for the member.
  final String name;

  /// Completion value between 0 and 1 for the day.
  final double completion;

  const GroupMemberProgressData({
    required this.uid,
    required this.name,
    required this.completion,
  });
}
