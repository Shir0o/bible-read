import 'package:flutter/material.dart';

import '../models/achievement_definition.dart';
import 'badge_icon.dart';
import 'common_styles.dart';

/// List item displaying an achievement badge with title and description.
class AchievementListItem extends StatelessWidget {
  /// Achievement definition to display.
  final AchievementDefinition definition;

  /// Whether the achievement has been unlocked.
  final bool unlocked;

  /// Creates an [AchievementListItem].
  const AchievementListItem({
    super.key,
    required this.definition,
    required this.unlocked,
  });

  @override
  Widget build(BuildContext context) {
    return CommonStyles.buildTappableCard(
      onTap: () {},
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: BadgeIcon(
          imageUrl: definition.imageUrl,
          iconData: definition.icon,
          locked: !unlocked,
          size: 48,
        ),
        title: Text(definition.title),
        subtitle: Text(definition.description),
      ),
    );
  }
}
