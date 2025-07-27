class AchievementDefinition {
  /// Unique id of the achievement.
  final String id;

  /// Display title of the achievement.
  final String title;

  /// Description of how to earn the achievement.
  final String description;

  /// Asset path for the badge icon.
  final String assetPath;

  /// Creates an [AchievementDefinition].
  const AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.assetPath,
  });
}

/// All achievements that can be unlocked in the app.
const List<AchievementDefinition> allAchievements = [
  AchievementDefinition(
    id: 'firstReader',
    title: 'First Reader',
    description: 'Be the first person to log reading for the day.',
    assetPath: 'assets/achievements/first_reader.png',
  ),
  AchievementDefinition(
    id: 'streak7',
    title: '7-Day Streak',
    description: 'Read the Bible seven days in a row.',
    assetPath: 'assets/achievements/streak7.png',
  ),
  AchievementDefinition(
    id: 'days30',
    title: '30 Days Read',
    description: 'Log 30 days of reading.',
    assetPath: 'assets/achievements/days30.png',
  ),
  AchievementDefinition(
    id: 'streak30',
    title: '30-Day Streak',
    description: 'Read every day for a full month.',
    assetPath: 'assets/achievements/streak30.png',
  ),
];
