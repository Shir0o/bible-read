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

    test('slugify handles special characters', () {
      expect(slugify('Genesis'), 'genesis');
      expect(slugify('1 Samuel'), '1_samuel');
      expect(slugify('Song of Songs'), 'song_of_songs');
      expect(slugify('  Trim Me  '), 'trim_me');
    });

    test('bookAchievementId generates correct ids', () {
      expect(
          AchievementDefinition.bookAchievementId('Genesis'), 'book_genesis');
      expect(AchievementDefinition.bookAchievementId('1 John'), 'book_1_john');
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
          .map((book) => AchievementDefinition.bookAchievementId(book))
          .toList(growable: false);
      expect(
        bookAchievements.map((a) => a.id).toList(growable: false),
        expectedIds,
      );
    });
  });
}
