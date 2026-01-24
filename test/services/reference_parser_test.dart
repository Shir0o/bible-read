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
        equals(
          <String>[
            'John 3',
            'John 4',
            'John 5',
            'Deuteronomy 28',
            'Deuteronomy 29',
            'Deuteronomy 30',
            'Deuteronomy 31',
          ],
        ),
      );
      expect(result.every(isCanonical), isTrue);
    });

    test('handles mixed delimiters across ranges', () {
      final result = ReferenceParser.parseChaptersList(
        'John 1; Mark 2 to 3; Luke 4–5; Acts 1 — 2',
      );

      expect(
        result,
        equals(
          <String>[
            'John 1',
            'Mark 2',
            'Mark 3',
            'Luke 4',
            'Luke 5',
            'Acts 1',
            'Acts 2',
          ],
        ),
      );
      expect(result.every(isCanonical), isTrue);
    });

    test('parses ordinal book names', () {
      final result = ReferenceParser.parseChaptersList('II Tim 3, 1 John 2');

      expect(
        result,
        equals(
          <String>[
            '2 Timothy 3',
            '1 John 2',
          ],
        ),
      );
      expect(result.every(isCanonical), isTrue);
    });

    test('falls back to normalizeOne for invalid inputs', () {
      const invalid = 'Mystery 5';
      const valid = 'Psalm 23';

      final result = ReferenceParser.parseChaptersList('$invalid; $valid');

      final normalizedInvalid = ReferenceParser.normalizeOne(invalid);

      expect(result, equals(<String>[normalizedInvalid, valid]));
      expect(result.every(isCanonical), isTrue);
    });

    test('expands cross-book ranges', () {
      final result = ReferenceParser.parseChaptersList('Genesis 50 - Exodus 2');

      expect(
        result,
        equals(
          <String>[
            'Genesis 50',
            'Exodus 1',
            'Exodus 2',
          ],
        ),
      );
      expect(result.every(isCanonical), isTrue);
    });

    test('expands complex cross-book ranges', () {
      final result = ReferenceParser.parseChaptersList('2 John 1 - 3 John 1');

      expect(
        result,
        equals(
          <String>[
            '2 John 1',
            '3 John 1',
          ],
        ),
      );
      expect(result.every(isCanonical), isTrue);
    });
  });

  group('ReferenceParser.nextChapter', () {
    test('increments chapter within book', () {
      expect(ReferenceParser.nextChapter('Genesis 1'), 'Genesis 2');
    });

    test('crosses book boundary', () {
      expect(ReferenceParser.nextChapter('Genesis 50'), 'Exodus 1');
    });

    test('returns null at end of Bible', () {
      expect(ReferenceParser.nextChapter('Revelation 22'), isNull);
    });

    test('normalizes input before processing', () {
      expect(ReferenceParser.nextChapter('gen 1'), 'Genesis 2');
    });

    test('returns null for invalid input', () {
      expect(ReferenceParser.nextChapter('Invalid 1'), isNull);
    });
  });

  group('ReferenceParser.normalizeOne', () {
    test('normalizes book names', () {
      expect(ReferenceParser.normalizeOne('gen 1'), 'Genesis 1');
      expect(ReferenceParser.normalizeOne('ex 1'), 'Exodus 1');
    });

    test('preserves unknown books', () {
      expect(ReferenceParser.normalizeOne('Unknown 1'), 'Unknown 1');
    });

    test('handles ordinal books', () {
      expect(ReferenceParser.normalizeOne('1 jn 1'), '1 John 1');
      expect(ReferenceParser.normalizeOne('II kings 1'), '2 Kings 1');
    });

    test('does NOT clamp chapters (current behavior)', () {
      expect(ReferenceParser.normalizeOne('Genesis 100'), 'Genesis 100');
    });

    test('ignores invalid chapter numbers', () {
      expect(ReferenceParser.normalizeOne('Genesis 0'), 'Genesis 0');
    });
  });
}
