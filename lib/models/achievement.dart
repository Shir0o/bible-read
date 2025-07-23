class Achievement {
  /// Unique document id for this achievement.
  final String id;

  /// Display title of the achievement.
  final String title;

  /// Achievement type or category.
  final String type;

  /// Date this achievement was unlocked.
  final DateTime dateUnlocked;

  /// Creates an [Achievement].
  const Achievement({
    required this.id,
    required this.title,
    required this.type,
    required this.dateUnlocked,
  });
}
