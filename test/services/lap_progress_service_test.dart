import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/lap_coverage.dart';
import 'package:bible_read/models/read_through.dart';
import 'package:bible_read/services/lap_progress_service.dart';
import 'package:bible_read/services/read_through_service.dart';
import 'package:bible_read/services/reference_parser.dart';

/// Every chapter reference in [books], e.g. "Genesis 1" ... "Malachi 4".
List<String> allChaptersOf(List<String> books) => [
      for (final book in books)
        for (var c = 1; c <= (ReferenceParser.chapterCount(book) ?? 0); c++)
          '$book $c',
    ];

void main() {
  late FakeFirebaseFirestore firestore;
  late LapProgressService laps;
  late ReadThroughService readThroughs;
  const uid = 'alice';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    readThroughs = ReadThroughService(firestore: firestore);
    laps = LapProgressService(
      firestore: firestore,
      readThroughService: readThroughs,
    );
  });

  group('accumulating a lap', () {
    test('marked chapters land in the right testament', () async {
      final result =
          await laps.recordChapters(uid, ['Genesis 1', 'Matthew 1', 'John 3']);

      expect(result.coverage.oldTestament['Genesis'], {1});
      expect(result.coverage.newTestament['Matthew'], {1});
      expect(result.coverage.newTestament['John'], {3});
      expect(result.isMilestone, isFalse);
    });

    test('unparseable references are ignored, not fatal', () async {
      final result = await laps.recordChapters(
        uid,
        ['Genesis 1', 'Hesitations 4', ''],
      );

      expect(result.coverage.oldTestament, {
        'Genesis': {1},
      });
    });

    test(
        'an over-long chapter clamps to the end of the book, as the '
        'reference parser has always done', () async {
      final result = await laps.recordChapters(uid, ['Genesis 999']);

      expect(result.coverage.oldTestament['Genesis'], {50});
    });

    test('marking is additive across calls', () async {
      await laps.recordChapters(uid, ['Genesis 1']);
      final result = await laps.recordChapters(uid, ['Genesis 2']);

      expect(result.coverage.oldTestament['Genesis'], {1, 2});
    });

    test('a book is complete only when every chapter is in', () async {
      await laps.recordChapters(uid, ['Jude 1']);
      final jude = await laps.fetch(uid);
      expect(jude.isBookComplete('Jude'), isTrue);

      await laps.recordChapters(uid, ['Philemon 1']);
      expect((await laps.fetch(uid)).isBookComplete('Philemon'), isTrue);

      await laps.recordChapters(uid, ['Mark 1']);
      expect((await laps.fetch(uid)).isBookComplete('Mark'), isFalse);
    });
  });

  group('detecting a lap', () {
    test('finishing every New Testament book records a read-through', () async {
      final result =
          await laps.recordChapters(uid, allChaptersOf(LapCoverage.ntBooks));

      expect(result.isMilestone, isTrue);
      expect(result.completed.single.scope, ReadThroughScope.newTestament);
      expect(result.completed.single.source, ReadThroughSource.detected);
      expect(result.completed.single.lapNumber, 1);
    });

    test('the finished testament starts over and the other is untouched',
        () async {
      await laps.recordChapters(uid, ['Genesis 1', 'Genesis 2']);
      final result =
          await laps.recordChapters(uid, allChaptersOf(LapCoverage.ntBooks));

      expect(result.coverage.newTestament, isEmpty,
          reason: 'the New Testament lap resets');
      expect(result.coverage.oldTestament['Genesis'], {1, 2},
          reason: 'the Old Testament lap keeps accruing');
    });

    test('a second lap of the same testament can complete again', () async {
      await laps.recordChapters(uid, allChaptersOf(LapCoverage.ntBooks));
      final second =
          await laps.recordChapters(uid, allChaptersOf(LapCoverage.ntBooks));

      expect(second.completed.single.lapNumber, 2);
      expect(
        ReadThroughService.countsFrom(await readThroughs.fetchAll(uid))
            .newTestament,
        2,
      );
    });

    test('finishing both testaments derives a whole Bible', () async {
      await laps.recordChapters(uid, allChaptersOf(LapCoverage.ntBooks));
      final result =
          await laps.recordChapters(uid, allChaptersOf(LapCoverage.otBooks));

      expect(result.completed.map((r) => r.scope), [
        ReadThroughScope.oldTestament,
        ReadThroughScope.wholeBible,
      ]);

      final counts =
          ReadThroughService.countsFrom(await readThroughs.fetchAll(uid));
      expect(counts.wholeBible, 1);
    });

    test(
        'finishing the whole Bible in one marking completes both testaments '
        'and derives the Bible', () async {
      final result = await laps.recordChapters(
        uid,
        allChaptersOf(ReferenceParser.allBooks),
      );

      expect(result.completed.map((r) => r.scope), [
        ReadThroughScope.oldTestament,
        ReadThroughScope.newTestament,
        ReadThroughScope.wholeBible,
      ]);
      expect(result.coverage.oldTestament, isEmpty);
      expect(result.coverage.newTestament, isEmpty);
    });

    test('detected read-throughs queue for celebration', () async {
      await laps.recordChapters(uid, allChaptersOf(LapCoverage.ntBooks));

      final pending = await readThroughs.uncelebrated(uid);
      expect(pending.single.scope, ReadThroughScope.newTestament);
    });
  });

  group('seeding existing users', () {
    test('partial lifetime coverage becomes lap 1 in progress', () async {
      final result = await laps.seedFromLifetime(uid, {
        'Genesis': {1, 2, 3},
        'Matthew': {1},
      });

      expect(result.completed, isEmpty);
      expect(result.coverage.oldTestament['Genesis'], {1, 2, 3});
      expect(result.coverage.newTestament['Matthew'], {1});
    });

    test('a testament already covered is granted a silent read-through',
        () async {
      final lifetime = LapProgressService.chaptersFrom(
        allChaptersOf(LapCoverage.ntBooks),
      );
      final result = await laps.seedFromLifetime(uid, lifetime);

      expect(result.completed.single.scope, ReadThroughScope.newTestament);
      expect(result.completed.single.source, ReadThroughSource.migrated);
      expect(result.coverage.newTestament, isEmpty);
    });

    test('migrated read-throughs are never celebrated and never announced',
        () async {
      final lifetime = LapProgressService.chaptersFrom(
        allChaptersOf(ReferenceParser.allBooks),
      );
      await laps.seedFromLifetime(uid, lifetime);

      expect(await readThroughs.uncelebrated(uid), isEmpty);
      final rows = await readThroughs.fetchAll(uid);
      expect(rows.every((r) => !r.source.isAnnounceable), isTrue);
      expect(
        ReadThroughService.countsFrom(rows).wholeBible,
        1,
        reason: 'a fully covered Bible migrates as one whole Bible',
      );
    });

    test('isSeeded reports whether the one-time seed has run', () async {
      expect(await laps.isSeeded(uid), isFalse);
      await laps.seedFromLifetime(uid, const {});
      expect(await laps.isSeeded(uid), isTrue);
    });
  });

  group('testament split', () {
    test('matches the 39/27 split the app already uses', () {
      expect(LapCoverage.otBooks.length, 39);
      expect(LapCoverage.ntBooks.length, 27);
      expect(LapCoverage.otBooks.first, 'Genesis');
      expect(LapCoverage.otBooks.last, 'Malachi');
      expect(LapCoverage.ntBooks.first, 'Matthew');
      expect(LapCoverage.ntBooks.last, 'Revelation');
    });
  });
}
