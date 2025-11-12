import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/models/achievement_definition.dart';
import 'package:bible_read/services/reference_parser.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

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
          category: AchievementCategory.featured,
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
          category: AchievementCategory.featured,
        ),
        returnsNormally,
      );

      expect(
        () => AchievementDefinition(
          id: 'icon',
          title: 'Icon',
          description: 'uses icon',
          icon: FontAwesomeIcons.award,
          category: AchievementCategory.featured,
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
          category: AchievementCategory.featured,
        ),
        returnsNormally,
      );
    });

    test('allAchievements have unique ids and one badge source', () {
      final ids = <String>{};
      for (final achievement in allAchievements) {
        final sources = [
          achievement.imageUrl,
          achievement.icon,
          // ignore: deprecated_member_use_from_same_package
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

    test('includes scripture achievements for each canonical book in order',
        () {
      final bookAchievements =
          allAchievements.where((a) => a.id.startsWith('book_')).toList();
      final expectedBooks = ReferenceParser.allBooks;
      expect(bookAchievements.length, expectedBooks.length);
      for (var i = 0; i < expectedBooks.length; i++) {
        final book = expectedBooks[i];
        final achievement = bookAchievements[i];
        final chapters = ReferenceParser.chapterCount(book)!;
        expect(achievement.title, 'Complete $book');
        expect(
          achievement.description,
          'Log all $chapters ${chapters == 1 ? 'chapter' : 'chapters'} of $book.',
        );
        expect(achievement.icon, FontAwesomeIcons.book);
      }

      final expectedIds = expectedBooks
          .map((book) => 'book_${_testSlugify(book)}')
          .toList(growable: false);
      expect(
        bookAchievements.map((a) => a.id).toList(growable: false),
        expectedIds,
      );
    });
  });
}

String _testSlugify(String input) {
  return input
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}
