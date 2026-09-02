import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/plan_day_list.dart';

void main() {
  group('formatChapterRun', () {
    test('collapses consecutive chapters of one book into a range', () {
      expect(
        formatChapterRun(['Jeremiah 2', 'Jeremiah 3']),
        'Jeremiah 2–3',
      );
      expect(
        formatChapterRun(['Jeremiah 10', 'Jeremiah 11', 'Jeremiah 12']),
        'Jeremiah 10–12',
      );
    });

    test('leaves a single chapter alone', () {
      expect(formatChapterRun(['Jeremiah 1']), 'Jeremiah 1');
    });

    test('names both books when a day spans a boundary', () {
      expect(
        formatChapterRun(['Jeremiah 52', 'Lamentations 1']),
        'Jeremiah 52 · Lamentations 1',
      );
    });

    test('does not merge a gap in chapters', () {
      expect(
        formatChapterRun(['Psalm 1', 'Psalm 3']),
        'Psalm 1 · Psalm 3',
      );
    });

    test('shows an unparseable reference verbatim', () {
      expect(formatChapterRun(['Nonsense']), 'Nonsense');
    });

    test('an empty day renders as nothing', () {
      expect(formatChapterRun(const []), '');
    });
  });

  group('formatPlanDate', () {
    test('reads as the rest of the app formats dates', () {
      expect(formatPlanDate(DateTime(2026, 9, 1)), 'Tue, Sep 1');
      expect(formatPlanDateShort(DateTime(2026, 9, 1)), 'Sep 1');
    });
  });
}
