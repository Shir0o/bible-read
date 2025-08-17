import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:bible_read/models/achievement_definition.dart';

void main() {
  group('AchievementDefinition', () {
    test('asserts when multiple badge sources are provided', () {
      expect(
        () => AchievementDefinition(
          id: 'test',
          title: 'Test',
          description: 'desc',
          imageUrl: 'https://example.com/badge.png',
          icon: FontAwesomeIcons.award,
        ),
        throwsAssertionError,
      );
    });

    test('constructs with exactly one badge source', () {
      expect(
        () => AchievementDefinition(
          id: 'url',
          title: 'URL',
          description: 'uses image url',
          imageUrl: 'https://example.com/badge.png',
        ),
        returnsNormally,
      );

      expect(
        () => AchievementDefinition(
          id: 'icon',
          title: 'Icon',
          description: 'uses icon',
          icon: FontAwesomeIcons.award,
        ),
        returnsNormally,
      );

      expect(
        // ignore: deprecated_member_use_from_same_package
        () => AchievementDefinition(
          id: 'asset',
          title: 'Asset',
          description: 'uses asset path',
          // ignore: deprecated_member_use_from_same_package
          assetPath: 'assets/badge.png',
        ),
        returnsNormally,
      );
    });

    test('allAchievements have unique ids and one badge source', () {
      final ids = <String>{};
      for (final achievement in allAchievements) {
        // ignore: deprecated_member_use_from_same_package
        final sources = [
          achievement.imageUrl,
          achievement.icon,
          achievement.assetPath
        ].where((s) => s != null).length;
        expect(
          sources,
          1,
          reason: '${achievement.id} must have exactly one badge source',
        );
        expect(ids.add(achievement.id), isTrue,
            reason: 'Duplicate id ${achievement.id}');
      }
    });
  });
}
