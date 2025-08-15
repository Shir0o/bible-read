import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/widgets.dart';

class AchievementDefinition {
  /// Unique id of the achievement.
  final String id;

  /// Display title of the achievement.
  final String title;

  /// Description of how to earn the achievement.
  final String description;

  /// URL to an image representing the badge.
  final String? imageUrl;

  /// Icon representing the badge.
  final IconData? icon;

  /// Local asset for the badge image. Deprecated in favor of [imageUrl] or
  /// [icon].
  @Deprecated('Use imageUrl or icon instead.')
  final String? assetPath;

  /// Creates an [AchievementDefinition]. Provide exactly one of [imageUrl],
  /// [icon], or [assetPath].
  const AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    this.imageUrl,
    this.icon,
    @Deprecated('Use imageUrl or icon instead.') this.assetPath,
  }) : assert(
          (imageUrl != null ? 1 : 0) +
                  (icon != null ? 1 : 0) +
                  (assetPath != null ? 1 : 0) ==
              1,
          'Provide exactly one badge source.',
        );
}

/// All achievements that can be unlocked in the app.
const List<AchievementDefinition> allAchievements = [
  AchievementDefinition(
    id: 'firstReader',
    title: 'First Reader',
    description: 'Be the first person to log reading for the day.',
    icon: FontAwesomeIcons.bookOpenReader,
  ),
  AchievementDefinition(
    id: 'streak7',
    title: '7-Day Streak',
    description: 'Read the Bible seven days in a row.',
    icon: FontAwesomeIcons.fire,
  ),
  AchievementDefinition(
    id: 'days30',
    title: '30 Days Read',
    description: 'Log 30 days of reading.',
    icon: FontAwesomeIcons.calendarCheck,
  ),
  AchievementDefinition(
    id: 'streak30',
    title: '30-Day Streak',
    description: 'Read every day for a full month.',
    icon: FontAwesomeIcons.fireFlameCurved,
  ),
];
