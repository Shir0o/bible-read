import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/read_through.dart';
import 'package:bible_read/services/read_through_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ReadThroughService service;
  const uid = 'alice';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = ReadThroughService(firestore: firestore);
  });

  Future<List<ReadThrough>> detect(ReadThroughScope scope, DateTime when) =>
      service.recordDetected(uid: uid, scope: scope, completedAt: when);

  List<ReadThrough> ofScope(List<ReadThrough> rows, ReadThroughScope s) =>
      rows.where((r) => r.scope == s).toList();

  group('whole-Bible derivation', () {
    test('a lone New Testament derives no whole Bible', () async {
      await detect(ReadThroughScope.newTestament, DateTime(2025, 11, 12));

      final rows = await service.fetchAll(uid);
      final counts = ReadThroughService.countsFrom(rows);

      expect(counts.newTestament, 1);
      expect(counts.oldTestament, 0);
      expect(counts.wholeBible, 0);
      expect(ofScope(rows, ReadThroughScope.wholeBible), isEmpty);
    });

    test('an Old Testament closing a pair derives one whole Bible', () async {
      await detect(ReadThroughScope.newTestament, DateTime(2025, 11, 12));
      final created =
          await detect(ReadThroughScope.oldTestament, DateTime(2026, 3, 4));

      // The testament record plus the whole Bible it just completed.
      expect(created.map((r) => r.scope), [
        ReadThroughScope.oldTestament,
        ReadThroughScope.wholeBible,
      ]);

      final rows = await service.fetchAll(uid);
      expect(ReadThroughService.countsFrom(rows).wholeBible, 1);
      expect(ofScope(rows, ReadThroughScope.wholeBible).single.completedAt,
          DateTime(2026, 3, 4));
    });

    test(
        'the derived record is dated when the pair closed, not when the '
        'earlier half finished', () async {
      await detect(ReadThroughScope.oldTestament, DateTime(2020, 1, 1));
      await detect(ReadThroughScope.newTestament, DateTime(2026, 9, 5));

      final rows = await service.fetchAll(uid);
      final bible = ofScope(rows, ReadThroughScope.wholeBible).single;

      expect(bible.completedAt, DateTime(2026, 9, 5));
      expect(bible.source, ReadThroughSource.derived);
    });

    test('three New Testaments and two Old make two whole Bibles', () async {
      await detect(ReadThroughScope.newTestament, DateTime(2024, 1, 1));
      await detect(ReadThroughScope.oldTestament, DateTime(2024, 6, 1));
      await detect(ReadThroughScope.newTestament, DateTime(2025, 1, 1));
      await detect(ReadThroughScope.oldTestament, DateTime(2025, 6, 1));
      await detect(ReadThroughScope.newTestament, DateTime(2026, 1, 1));

      final rows = await service.fetchAll(uid);
      final counts = ReadThroughService.countsFrom(rows);

      expect(counts.newTestament, 3);
      expect(counts.oldTestament, 2);
      expect(counts.wholeBible, 2, reason: 'min(3, 2)');
      expect(ofScope(rows, ReadThroughScope.wholeBible).length, 2,
          reason: 'stored derived records must match the derived count');
    });

    test('stored whole-Bible records always equal min(OT, NT)', () async {
      final scopes = [
        ReadThroughScope.newTestament,
        ReadThroughScope.newTestament,
        ReadThroughScope.oldTestament,
        ReadThroughScope.newTestament,
        ReadThroughScope.oldTestament,
        ReadThroughScope.oldTestament,
        ReadThroughScope.oldTestament,
      ];
      for (var i = 0; i < scopes.length; i++) {
        await detect(scopes[i], DateTime(2024, 1, 1).add(Duration(days: i)));

        final rows = await service.fetchAll(uid);
        final counts = ReadThroughService.countsFrom(rows);
        expect(
          ofScope(rows, ReadThroughScope.wholeBible).length,
          counts.wholeBible,
          reason: 'after ${i + 1} record(s)',
        );
      }

      final counts = ReadThroughService.countsFrom(await service.fetchAll(uid));
      expect(counts.newTestament, 3);
      expect(counts.oldTestament, 4);
      expect(counts.wholeBible, 3);
    });
  });

  group('lap numbers', () {
    test('number within a scope, oldest first', () async {
      await detect(ReadThroughScope.newTestament, DateTime(2024, 1, 1));
      await detect(ReadThroughScope.newTestament, DateTime(2025, 1, 1));
      final created =
          await detect(ReadThroughScope.newTestament, DateTime(2026, 1, 1));

      expect(created.single.lapNumber, 3);
      expect(created.single.ordinalLabel, '3rd time');
    });

    test('each scope counts separately', () async {
      await detect(ReadThroughScope.newTestament, DateTime(2024, 1, 1));
      final created =
          await detect(ReadThroughScope.oldTestament, DateTime(2025, 1, 1));

      final ot = created.firstWhere(
        (r) => r.scope == ReadThroughScope.oldTestament,
      );
      expect(ot.lapNumber, 1, reason: 'first Old Testament, not third record');
    });
  });

  group('backfill', () {
    test(
        'a whole-Bible backfill records both testaments and derives one '
        'whole Bible', () async {
      await service.addBackfilled(
        uid: uid,
        scope: ReadThroughScope.wholeBible,
        completedAt: DateTime(2011, 1, 1),
        precision: DatePrecision.year,
        location: 'Fuller, Pasadena',
      );

      final rows = await service.fetchAll(uid);
      final counts = ReadThroughService.countsFrom(rows);

      expect(counts.oldTestament, 1);
      expect(counts.newTestament, 1);
      expect(counts.wholeBible, 1);
      expect(ofScope(rows, ReadThroughScope.wholeBible).single.location,
          'Fuller, Pasadena');
    });

    test('backfilled records are never celebrated', () async {
      await service.addBackfilled(
        uid: uid,
        scope: ReadThroughScope.oldTestament,
        completedAt: DateTime(2011),
        precision: DatePrecision.year,
      );

      expect(await service.uncelebrated(uid), isEmpty);
    });

    test('a whole Bible derived from backfill is not celebrated', () async {
      await service.addBackfilled(
        uid: uid,
        scope: ReadThroughScope.wholeBible,
        completedAt: DateTime(2011),
        precision: DatePrecision.year,
      );

      expect(await service.uncelebrated(uid), isEmpty);
    });
  });

  group('celebration queue', () {
    test('detected records queue until marked', () async {
      final created =
          await detect(ReadThroughScope.newTestament, DateTime(2026, 9, 5));

      var pending = await service.uncelebrated(uid);
      expect(pending.length, 1);

      await service.markCelebrated(uid, [created.single.id]);
      pending = await service.uncelebrated(uid);
      expect(pending, isEmpty);
    });

    test('a detected record and the whole Bible it closes queue together',
        () async {
      await detect(ReadThroughScope.oldTestament, DateTime(2026, 3, 4));
      await service.markCelebrated(
        uid,
        (await service.uncelebrated(uid)).map((r) => r.id),
      );

      await detect(ReadThroughScope.newTestament, DateTime(2026, 9, 5));
      final pending = await service.uncelebrated(uid);

      expect(pending.map((r) => r.scope), [
        ReadThroughScope.newTestament,
        ReadThroughScope.wholeBible,
      ]);
    });
  });

  group('deletion', () {
    test('a detected record cannot be deleted', () async {
      final created =
          await detect(ReadThroughScope.newTestament, DateTime(2026, 9, 5));

      expect(
        () => service.delete(uid, created.single.id),
        throwsA(isA<StateError>()),
      );
    });

    test('deleting a backfilled half removes the whole Bible it propped up',
        () async {
      final backfilled = await service.addBackfilled(
        uid: uid,
        scope: ReadThroughScope.oldTestament,
        completedAt: DateTime(2011),
        precision: DatePrecision.year,
      );
      await detect(ReadThroughScope.newTestament, DateTime(2026, 9, 5));

      var rows = await service.fetchAll(uid);
      expect(ReadThroughService.countsFrom(rows).wholeBible, 1);

      await service.delete(uid, backfilled.first.id);

      rows = await service.fetchAll(uid);
      expect(ReadThroughService.countsFrom(rows).wholeBible, 0);
      expect(ofScope(rows, ReadThroughScope.wholeBible), isEmpty);
    });
  });

  group('date rendering', () {
    test('renders at the precision the user gave', () {
      ReadThrough at(DatePrecision p) => ReadThrough(
            id: 'x',
            scope: ReadThroughScope.wholeBible,
            completedAt: DateTime(2011, 3, 12),
            datePrecision: p,
            source: ReadThroughSource.backfilled,
          );

      expect(at(DatePrecision.year).dateLabel, '2011');
      expect(at(DatePrecision.month).dateLabel, 'March 2011');
      expect(at(DatePrecision.day).dateLabel, '12 March 2011');
    });

    test('appends the location when there is one', () {
      final row = ReadThrough(
        id: 'x',
        scope: ReadThroughScope.wholeBible,
        completedAt: DateTime(2011),
        datePrecision: DatePrecision.year,
        location: 'Taipei',
        source: ReadThroughSource.backfilled,
      );
      expect(row.subtitle, '2011 · Taipei');
    });
  });
}
