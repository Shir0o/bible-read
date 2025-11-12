import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:bible_read/services/reference_parser.dart';

/// Available groupings for achievements shown in the UI.
enum AchievementCategory {
  /// Core achievements such as streaks and milestones.
  featured,

  /// Individual book completion achievements.
  book,
}

extension AchievementCategoryDisplayName on AchievementCategory {
  String get label {
    switch (this) {
      case AchievementCategory.featured:
        return 'Featured';
      case AchievementCategory.book:
        return 'Books';
    }
  }
}

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

  /// Category the achievement belongs to.
  final AchievementCategory category;

  /// Creates an [AchievementDefinition]. Provide exactly one of [imageUrl],
  /// [icon], or [assetPath].
  const AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
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
final List<AchievementDefinition> allAchievements = _buildAllAchievements();

const List<AchievementDefinition> _coreAchievements = [
  AchievementDefinition(
    id: 'firstReader',
    title: 'First Reader',
    description: 'Be the first person to log reading for the day.',
    icon: FontAwesomeIcons.bookOpenReader,
    category: AchievementCategory.featured,
  ),
  AchievementDefinition(
    id: 'streak7',
    title: '7-Day Streak',
    description: 'Read the Bible seven days in a row.',
    icon: FontAwesomeIcons.fire,
    category: AchievementCategory.featured,
  ),
  AchievementDefinition(
    id: 'days30',
    title: '30 Days Read',
    description: 'Log 30 days of reading.',
    icon: FontAwesomeIcons.calendarCheck,
    category: AchievementCategory.featured,
  ),
  AchievementDefinition(
    id: 'streak30',
    title: '30-Day Streak',
    description: 'Read every day for a full month.',
    icon: FontAwesomeIcons.fireFlameCurved,
    category: AchievementCategory.featured,
  ),
];

List<AchievementDefinition> _buildAllAchievements() {
  final achievements = <AchievementDefinition>[
    ..._coreAchievements,
    ..._buildScriptureAchievements(),
  ];
  return List.unmodifiable(achievements);
}

List<AchievementDefinition> _buildScriptureAchievements() {
  return ReferenceParser.allBooks.map((book) {
    final chapters = ReferenceParser.chapterCount(book)!;
    final chapterLabel = chapters == 1 ? 'chapter' : 'chapters';
    return AchievementDefinition(
      id: 'book_${_slugify(book)}',
      title: 'Complete $book',
      description: 'Log all $chapters $chapterLabel of $book.',
      icon: FontAwesomeIcons.book,
      category: AchievementCategory.book,
    );
  }).toList(growable: false);
}

/// Returns an unmodifiable list of achievements belonging to [category].
List<AchievementDefinition> achievementsForCategory(
  AchievementCategory category,
) {
  return List<AchievementDefinition>.unmodifiable(
    allAchievements.where((achievement) => achievement.category == category),
  );
}

String _slugify(String input) {
  final slug = input
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return slug;
}
