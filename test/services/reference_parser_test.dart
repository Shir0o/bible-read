import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/services/reference_parser.dart';

void main() {
  group('ReferenceParser.parseChaptersList', () {
    bool isCanonical(String ref) {
      final canonicalPattern = RegExp(r'^[1-3]? ?[A-Za-z][A-Za-z ]+ [0-9]+$');
      return canonicalPattern.hasMatch(ref);
    }

    test('expands ranges and canonicalizes book names', () {
      final result = ReferenceParser.parseChaptersList('John 3-5; deut 28-31');

      expect(
        result,
        equals(<String>[
          'John 3',
          'John 4',
          'John 5',
          'Deuteronomy 28',
          'Deuteronomy 29',
          'Deuteronomy 30',
          'Deuteronomy 31',
        ]),
      );
      expect(result.every(isCanonical), isTrue);
    });

    test('handles mixed delimiters across ranges', () {
      final result = ReferenceParser.parseChaptersList(
        'John 1; Mark 2 to 3; Luke 4–5; Acts 1 — 2',
      );

      expect(
        result,
        equals(<String>[
          'John 1',
          'Mark 2',
          'Mark 3',
          'Luke 4',
          'Luke 5',
          'Acts 1',
          'Acts 2',
        ]),
      );
      expect(result.every(isCanonical), isTrue);
    });

    test('parses ordinal book names', () {
      final result = ReferenceParser.parseChaptersList('II Tim 3, 1 John 2');

      expect(result, equals(<String>['2 Timothy 3', '1 John 2']));
      expect(result.every(isCanonical), isTrue);
    });

    test('falls back to normalizeOne for invalid inputs', () {
      const invalid = 'Mystery 5';
      const valid = 'Psalm 23';

      final result = ReferenceParser.parseChaptersList('$invalid; $valid');

      // invalid input returns trimmed input if parsing fails
      expect(result, equals(<String>[invalid, valid]));
    });

    test('expands cross-book ranges', () {
      final result = ReferenceParser.parseChaptersList('Genesis 50 - Exodus 2');

      expect(result, equals(<String>['Genesis 50', 'Exodus 1', 'Exodus 2']));
      expect(result.every(isCanonical), isTrue);
    });

    test('expands complex cross-book ranges', () {
      final result = ReferenceParser.parseChaptersList('2 John 1 - 3 John 1');

      expect(result, equals(<String>['2 John 1', '3 John 1']));
      expect(result.every(isCanonical), isTrue);
    });

    test('parses comma-separated list with implied book', () {
      final result = ReferenceParser.parseChaptersList('John 3, 4');
      expect(result, equals(['John 3', 'John 4']));
      expect(result.every(isCanonical), isTrue);
    });

    test('parses ambiguous ranges deterministically', () {
      // "Gen 1-2-3" is parsed by splitting on '-' into ["Gen 1", "2", "3"].
      // The logic takes start="Gen 1" and end="3", ignoring intermediate "2".
      // range(Gen 1, Gen 3) -> Gen 1, Gen 2, Gen 3.
      final result = ReferenceParser.parseChaptersList('Gen 1-2-3');
      expect(result, equals(['Genesis 1', 'Genesis 2', 'Genesis 3']));
      expect(result.every(isCanonical), isTrue);
    });

    test('handles reversed ranges', () {
      final result = ReferenceParser.parseChaptersList('John 5-3');
      expect(result, equals(<String>['John 3', 'John 4', 'John 5']));
      expect(result.every(isCanonical), isTrue);
    });

    test('preserves invalid chapter 0 instead of coercing to 1', () {
      // Previously coerced to 'Genesis 1'. Now should fall back to raw input.
      final result = ReferenceParser.parseChaptersList('Gen 0');
      expect(result, equals(['Gen 0']));
    });
  });

  group('ReferenceParser.nextChapter', () {
    test('returns next chapter in same book', () {
      expect(ReferenceParser.nextChapter('Genesis 1'), 'Genesis 2');
      expect(ReferenceParser.nextChapter('John 3'), 'John 4');
    });

    test('returns first chapter of next book when current book ends', () {
      expect(ReferenceParser.nextChapter('Genesis 50'), 'Exodus 1');
      expect(ReferenceParser.nextChapter('Malachi 4'), 'Matthew 1');
    });

    test('returns null for last chapter of Revelation', () {
      expect(ReferenceParser.nextChapter('Revelation 22'), isNull);
    });

    test('returns null for invalid inputs', () {
      expect(ReferenceParser.nextChapter(''), isNull);
      expect(ReferenceParser.nextChapter('NotABook 1'), isNull);
      expect(ReferenceParser.nextChapter('Genesis'), isNull); // missing chapter
    });

    test('clamps and advances out-of-range chapters', () {
      // Genesis 100 clamps to Genesis 50, so next is Exodus 1
      expect(ReferenceParser.nextChapter('Genesis 100'), 'Exodus 1');
    });
  });

  group('ReferenceParser.chapterCount', () {
    test('returns correct count for valid books', () {
      expect(ReferenceParser.chapterCount('Genesis'), 50);
      expect(ReferenceParser.chapterCount('Psalm'), 150);
      expect(ReferenceParser.chapterCount('2 John'), 1);
    });

    test('handles abbreviations and casing', () {
      expect(ReferenceParser.chapterCount('gen'), 50);
      expect(ReferenceParser.chapterCount('GENESIS'), 50);
      expect(ReferenceParser.chapterCount('jn'), 21);
    });

    test('returns null for invalid books', () {
      expect(ReferenceParser.chapterCount('Mystery'), isNull);
      expect(ReferenceParser.chapterCount(''), isNull);
    });
  });

  group('ReferenceParser.normalizeOne', () {
    test('normalizes valid references', () {
      expect(ReferenceParser.normalizeOne('jn 3:16'), 'John 3');
      expect(ReferenceParser.normalizeOne('  gen   1  '), 'Genesis 1');
    });

    test('returns original string for invalid references', () {
      expect(ReferenceParser.normalizeOne('Mystery 5'), 'Mystery 5');
      expect(ReferenceParser.normalizeOne('Genesis -1'), 'Genesis -1');
      expect(ReferenceParser.normalizeOne('Genesis 0'), 'Genesis 0');
    });

    test('handles ordinals', () {
      expect(ReferenceParser.normalizeOne('1 john 1'), '1 John 1');
      expect(ReferenceParser.normalizeOne('ii kings 2'), '2 Kings 2');
    });

    test('clamps out-of-range chapters', () {
      expect(ReferenceParser.normalizeOne('Genesis 100'), 'Genesis 50');
      expect(ReferenceParser.normalizeOne('Jude 2'), 'Jude 1');
    });
  });
}
