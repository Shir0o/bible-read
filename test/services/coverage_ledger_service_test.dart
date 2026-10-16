import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/models/lap_coverage.dart';
import 'package:bible_read/models/read_through.dart';
import 'package:bible_read/services/coverage_ledger_service.dart';
import 'package:bible_read/services/lap_progress_service.dart';
import 'package:bible_read/services/milestone_announcer.dart';
import 'package:bible_read/services/read_through_service.dart';
import 'package:bible_read/services/reference_parser.dart';

import 'lap_progress_service_test.dart' show allChaptersOf;

class _FakeAnnouncer extends MilestoneAnnouncer {
  _FakeAnnouncer() : super(firestore: FakeFirebaseFirestore());

  final List<List<ReadThrough>> announced = [];

  @override
  Future<void> announce({
    required String uid,
    required List<ReadThrough> completed,
    DateTime? now,
  }) async {
    announced.add(completed);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late _FakeAnnouncer announcer;
  late LapProgressService lapService;
  late ReadThroughService readThroughService;
  late CoverageLedgerService service;
  const uid = 'alice';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    announcer = _FakeAnnouncer();
    readThroughService = ReadThroughService(firestore: firestore);
    lapService = LapProgressService(
      firestore: firestore,
      readThroughService: readThroughService,
    );
    service = CoverageLedgerService(
      firestore: firestore,
      lapService: lapService,
      readThroughService: readThroughService,
      announcer: announcer,
    );
  });

  Future<void> savePlan(
      String planId, List<Map<String, dynamic>> schedule) async {
    await firestore.collection('custom_plans').doc(planId).set({
      'title': 'Plan $planId',
      'description': '',
      'durationDays': schedule.length,
      'tags': <String>[],
      'schedule': schedule,
    });
  }

  group('Chapter Crediting', () {
    test('creditChapters accumulates into lap coverage', () async {
      final result = await service.creditChapters(
        uid,
        ['Genesis 1', 'Matthew 1'],
      );

      expect(result.coverage.oldTestament['Genesis'], {1});
      expect(result.coverage.newTestament['Matthew'], {1});
      expect(announcer.announced, isEmpty);
    });

    test('creditChapters handles empty references gracefully', () async {
      final result = await service.creditChapters(uid, []);
      expect(result.completed, isEmpty);
      expect(result.coverage.oldTestament, isEmpty);
    });

    test('creditChapters announces when a milestone is completed', () async {
      final result = await service.creditChapters(
        uid,
        allChaptersOf(LapCoverage.ntBooks),
      );

      expect(result.isMilestone, isTrue);
      expect(result.completed.single.scope, ReadThroughScope.newTestament);
      expect(announcer.announced.length, 1);
      expect(
          announcer.announced.first.first.scope, ReadThroughScope.newTestament);
    });

    test('creditChapters does not announce when silent is true', () async {
      final result = await service.creditChapters(
        uid,
        allChaptersOf(LapCoverage.ntBooks),
        silent: true,
      );

      expect(result.isMilestone, isTrue);
      expect(announcer.announced, isEmpty);
    });

    test('creditGroupReading credits checked chapters and ignores out-of-range',
        () async {
      final schedule = GroupSchedule(
        date: DateTime(2026, 9, 5),
        chapters: const ['Genesis 1', 'Exodus 1', 'Matthew 1'],
      );

      await service.creditGroupReading(
        uid: uid,
        schedule: schedule,
        checkedIndices: const [-1, 0, 2, 5],
      );

      final coverage = await service.fetchLapCoverage(uid);
      expect(coverage.oldTestament['Genesis'], {1});
      expect(coverage.oldTestament['Exodus'], isNull);
      expect(coverage.newTestament['Matthew'], {1});
    });

    test('creditPlanDay credits all chapters listed for the scheduled day',
        () async {
      await savePlan('p1', [
        {
          'day': 1,
          'readings': ['Genesis 1', 'Genesis 2'],
        },
        {
          'day': 2,
          'readings': ['Genesis 3'],
        },
      ]);

      await service.creditPlanDay(uid: uid, planId: 'p1', day: 1);

      final coverage = await service.fetchLapCoverage(uid);
      expect(coverage.oldTestament['Genesis'], {1, 2});
    });

    test('creditPlanDaySilently credits chapters without announcing milestone',
        () async {
      await savePlan('p_nt', [
        {
          'day': 1,
          'readings': allChaptersOf(LapCoverage.ntBooks),
        },
      ]);

      await service.creditPlanDaySilently(uid: uid, planId: 'p_nt', day: 1);

      final counts = await service.fetchCounts(uid);
      expect(counts.newTestament, 1);
      expect(announcer.announced, isEmpty);
    });
  });

  group('Lap Coverage', () {
    test('watchLapCoverage and fetchLapCoverage report current lap', () async {
      expect((await service.fetchLapCoverage(uid)).oldTestament, isEmpty);

      final futureLap = service.watchLapCoverage(uid).firstWhere(
            (c) => c.oldTestament.containsKey('Genesis'),
          );

      await service.creditChapters(uid, ['Genesis 1']);

      final emitted = await futureLap;
      expect(emitted.oldTestament['Genesis'], {1});
    });

    test(
        'seedFromLifetime migrates partial progress and grants full testaments',
        () async {
      expect(await service.isSeeded(uid), isFalse);

      final ntLifetime = LapProgressService.chaptersFrom(
        allChaptersOf(LapCoverage.ntBooks),
      );
      final result = await service.seedFromLifetime(uid, {
        'Genesis': {1, 2},
        ...ntLifetime,
      });

      expect(await service.isSeeded(uid), isTrue);
      expect(result.coverage.oldTestament['Genesis'], {1, 2});
      expect(result.coverage.newTestament, isEmpty);
      expect(result.completed.single.scope, ReadThroughScope.newTestament);
      expect(result.completed.single.source, ReadThroughSource.migrated);
    });
  });

  group('Read-Throughs & Counts', () {
    test('fetchReadThroughs and watchCounts derive counts from ledger',
        () async {
      final initialCounts = await service.fetchCounts(uid);
      expect(initialCounts.wholeBible, 0);
      expect(initialCounts.oldTestament, 0);
      expect(initialCounts.newTestament, 0);

      await service.addBackfilled(
        uid: uid,
        scope: ReadThroughScope.newTestament,
        completedAt: DateTime(2025, 1, 1),
        precision: DatePrecision.month,
        location: 'Home',
      );

      final rows = await service.fetchReadThroughs(uid);
      expect(rows.length, 1);
      expect(rows.first.scope, ReadThroughScope.newTestament);
      expect(rows.first.location, 'Home');

      final counts = await service.fetchCounts(uid);
      expect(counts.newTestament, 1);
      expect(counts.oldTestament, 0);
      expect(counts.wholeBible, 0);
    });

    test('pairing testaments derives whole-Bible read-through', () async {
      await service.addBackfilled(
        uid: uid,
        scope: ReadThroughScope.wholeBible,
        completedAt: DateTime(2025, 2, 1),
        precision: DatePrecision.day,
      );

      final counts = await service.fetchCounts(uid);
      expect(counts.wholeBible, 1);
      expect(counts.oldTestament, 1);
      expect(counts.newTestament, 1);
    });

    test('updateReadThroughDetails and deleteReadThrough manage records',
        () async {
      final created = await service.addBackfilled(
        uid: uid,
        scope: ReadThroughScope.newTestament,
        completedAt: DateTime(2025, 1, 1),
        precision: DatePrecision.year,
        location: 'Camp',
      );
      final id = created.first.id;

      await service.updateReadThroughDetails(
        uid,
        id,
        location: 'New Camp',
        datePrecision: DatePrecision.day,
      );

      final updated = (await service.fetchReadThroughs(uid)).first;
      expect(updated.location, 'New Camp');
      expect(updated.datePrecision, DatePrecision.day);

      await service.deleteReadThrough(uid, id);
      expect(await service.fetchReadThroughs(uid), isEmpty);
    });

    test('uncelebrated and markCelebrated manage celebration queue', () async {
      await service.creditChapters(uid, allChaptersOf(LapCoverage.ntBooks));

      final unceleb = await service.uncelebrated(uid);
      expect(unceleb.length, 1);
      expect(unceleb.first.celebrated, isFalse);

      await service.markCelebrated(uid, [unceleb.first.id]);
      expect(await service.uncelebrated(uid), isEmpty);
    });
  });

  group('Book & Lifetime Chapter Coverage', () {
    test('unifyCoverage combines base group readings and current lap', () {
      final unified = CoverageLedgerService.unifyCoverage(
        baseGroupCoverage: {
          'Genesis': {1, 2},
          'John': {1},
        },
        lapCoverage: const LapCoverage(
          oldTestament: {
            'Genesis': {2, 3},
            'Exodus': {1},
          },
          newTestament: {
            'John': {1, 2},
          },
        ),
        readThroughs: const [],
      );

      expect(unified['Genesis'], {1, 2, 3});
      expect(unified['Exodus'], {1});
      expect(unified['John'], {1, 2});
    });

    test(
        'unifyCoverage completes all 39 OT books when OT read-through is completed',
        () {
      final otRecord = ReadThrough(
        id: '1',
        scope: ReadThroughScope.oldTestament,
        completedAt: DateTime(2025, 1, 1),
        datePrecision: DatePrecision.day,
        source: ReadThroughSource.detected,
      );

      final unified = CoverageLedgerService.unifyCoverage(
        baseGroupCoverage: const {},
        lapCoverage: LapCoverage.empty,
        readThroughs: [otRecord],
      );

      expect(unified.keys.length, 39);
      expect(unified['Genesis']!.length, 50);
      expect(unified['Malachi']!.length, 4);
      expect(unified['Matthew'], isNull);
    });

    test(
        'unifyCoverage completes all 27 NT books when NT read-through is completed',
        () {
      final ntRecord = ReadThrough(
        id: '2',
        scope: ReadThroughScope.newTestament,
        completedAt: DateTime(2025, 1, 1),
        datePrecision: DatePrecision.day,
        source: ReadThroughSource.detected,
      );

      final unified = CoverageLedgerService.unifyCoverage(
        baseGroupCoverage: const {},
        lapCoverage: LapCoverage.empty,
        readThroughs: [ntRecord],
      );

      expect(unified.keys.length, 27);
      expect(unified['Matthew']!.length, 28);
      expect(unified['Revelation']!.length, 22);
      expect(unified['Genesis'], isNull);
    });

    test('unifyCoverage includes manual book completions', () {
      final unified = CoverageLedgerService.unifyCoverage(
        baseGroupCoverage: const {},
        lapCoverage: LapCoverage.empty,
        readThroughs: const [],
        manualBooks: {'Ruth'},
      );

      expect(unified['Ruth'], {1, 2, 3, 4});
    });

    test(
        'completedChaptersByBook includes personal plan readings that legacy query missed',
        () async {
      await savePlan('p_solo', [
        {
          'day': 1,
          'readings': ['John 1', 'John 2', 'Genesis 1'],
        },
      ]);

      // Credit personal plan reading
      await service.creditPlanDay(uid: uid, planId: 'p_solo', day: 1);

      // Verify completedChaptersByBook includes this personal plan reading
      final coverage = await service.completedChaptersByBook(uid);
      expect(coverage['John'], {1, 2});
      expect(coverage['Genesis'], {1});
    });

    test(
        'completedChaptersByBook retains completed testament coverage even after lap resets',
        () async {
      // Complete New Testament via personal plan
      await service.creditChapters(
        uid,
        allChaptersOf(LapCoverage.ntBooks),
      );

      // Lap coverage has reset
      final lap = await service.fetchLapCoverage(uid);
      expect(lap.newTestament, isEmpty);

      // But completedChaptersByBook unifies with completed read-through
      final lifetime = await service.completedChaptersByBook(uid);
      for (final book in LapCoverage.ntBooks) {
        final totalChapters = ReferenceParser.chapterCount(book) ?? 0;
        expect(lifetime[book]?.length, totalChapters,
            reason:
                '$book should have all chapters complete in lifetime coverage');
      }
    });

    test('watchBookCoverage emits reactively when chapters are credited',
        () async {
      final coverageStream = service.watchBookCoverage(uid);

      final futureEmission = coverageStream.firstWhere(
        (data) => data.containsKey('Romans') && data['Romans']!.contains(1),
      );

      await service.creditChapters(uid, ['Romans 1']);

      final emitted = await futureEmission;
      expect(emitted['Romans'], {1});
    });

    test('setBookManualCompletion writes bible_books and credits lap',
        () async {
      await service.setBookManualCompletion(
        uid: uid,
        book: 'Ruth',
        completed: true,
      );

      final doc = await firestore
          .collection('users')
          .doc(uid)
          .collection('bible_books')
          .doc('Ruth')
          .get();
      expect(doc.exists, isTrue);

      final lap = await service.fetchLapCoverage(uid);
      expect(lap.oldTestament['Ruth'], {1, 2, 3, 4});

      expect(await service.getLastCheckedBook(uid), 'Ruth');

      // Un-marking
      await service.setBookManualCompletion(
        uid: uid,
        book: 'Ruth',
        completed: false,
      );
      final unmarkDoc = await firestore
          .collection('users')
          .doc(uid)
          .collection('bible_books')
          .doc('Ruth')
          .get();
      expect(unmarkDoc.exists, isFalse);
    });
  });
}
