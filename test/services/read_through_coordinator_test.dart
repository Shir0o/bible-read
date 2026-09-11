import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/lap_progress_service.dart';
import 'package:bible_read/services/read_through_coordinator.dart';
import 'package:bible_read/services/read_through_service.dart';
import 'package:bible_read/services/reference_parser.dart';

import 'lap_progress_service_test.dart' show allChaptersOf;

void main() {
  late FakeFirebaseFirestore firestore;
  late LapProgressService laps;
  late ReadThroughService readThroughs;
  late ReadThroughCoordinator coordinator;
  const uid = 'alice';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    readThroughs = ReadThroughService(firestore: firestore);
    laps = LapProgressService(
      firestore: firestore,
      readThroughService: readThroughs,
    );
    coordinator =
        ReadThroughCoordinator(firestore: firestore, lapService: laps);
  });

  group('group reading', () {
    test('checked chapters are credited to the lap', () async {
      await coordinator.creditGroupReading(
        uid: uid,
        schedule: GroupSchedule(
          date: DateTime(2026, 9, 5),
          chapters: const ['Genesis 1', 'Genesis 2', 'Matthew 1'],
        ),
        checkedIndices: const [0, 2],
      );

      final coverage = await laps.fetch(uid);
      expect(coverage.oldTestament['Genesis'], {1});
      expect(coverage.newTestament['Matthew'], {1});
    });

    test('a schedule with no chapters credits nothing', () async {
      await coordinator.creditGroupReading(
        uid: uid,
        schedule: GroupSchedule(date: DateTime(2026, 9, 5), chapters: const []),
        checkedIndices: const [0],
      );

      final coverage = await laps.fetch(uid);
      expect(coverage.oldTestament, isEmpty);
      expect(coverage.newTestament, isEmpty);
    });

    test('out-of-range indices are ignored', () async {
      await coordinator.creditGroupReading(
        uid: uid,
        schedule: GroupSchedule(
          date: DateTime(2026, 9, 5),
          chapters: const ['Genesis 1'],
        ),
        checkedIndices: const [-1, 0, 7],
      );

      expect((await laps.fetch(uid)).oldTestament, {
        'Genesis': {1},
      });
    });
  });

  group('marking a group day through GroupService', () {
    late GroupService groups;

    setUp(() {
      groups = GroupService(
        firestore: firestore,
        readThroughCoordinator: coordinator,
      );
    });

    test('marking read credits the day to the lap', () async {
      final ok = await groups.toggleReadStatus(
        groupId: 'g1',
        uid: uid,
        schedule: GroupSchedule(
          date: DateTime(2026, 9, 5),
          chapters: const ['Genesis 1', 'Genesis 2'],
        ),
        read: true,
      );

      expect(ok, isTrue);
      expect((await laps.fetch(uid)).oldTestament['Genesis'], {1, 2});
    });

    test('un-marking never takes the lap back', () async {
      final schedule = GroupSchedule(
        date: DateTime(2026, 9, 5),
        chapters: const ['Genesis 1'],
      );
      await groups.toggleReadStatus(
        groupId: 'g1',
        uid: uid,
        schedule: schedule,
        read: true,
      );
      await groups.toggleReadStatus(
        groupId: 'g1',
        uid: uid,
        schedule: schedule,
        read: false,
        currentlyChecked: const {0},
      );

      expect((await laps.fetch(uid)).oldTestament['Genesis'], {1},
          reason: 'coupling only ever flows one way');
    });

    test('the marking that finishes a testament records the read-through',
        () async {
      final ok = await groups.toggleReadStatus(
        groupId: 'g1',
        uid: uid,
        schedule: GroupSchedule(
          date: DateTime(2026, 9, 5),
          chapters: allChaptersOf(ReferenceParser.allBooks.sublist(39)),
        ),
        read: true,
      );

      expect(ok, isTrue);
      final counts =
          ReadThroughService.countsFrom(await readThroughs.fetchAll(uid));
      expect(counts.newTestament, 1);
      expect((await laps.fetch(uid)).newTestament, isEmpty);
    });
  });

  group('plan days', () {
    Future<void> savePlan(List<Map<String, dynamic>> schedule) async {
      await firestore.collection('custom_plans').doc('p1').set({
        'title': 'Test plan',
        'description': '',
        'durationDays': schedule.length,
        'tags': <String>[],
        'schedule': schedule,
      });
    }

    test('a completed day credits every chapter that day listed', () async {
      await savePlan([
        {
          'day': 1,
          'readings': ['Genesis 1', 'Genesis 2', 'Genesis 3'],
        },
        {
          'day': 2,
          'readings': ['Genesis 4'],
        },
      ]);

      await coordinator.creditPlanDay(uid: uid, planId: 'p1', day: 1);

      expect((await laps.fetch(uid)).oldTestament['Genesis'], {1, 2, 3},
          reason: 'plan progress is stored per day, so a day credits its '
              'whole reading');
    });

    test('a day that is not in the plan credits nothing', () async {
      await savePlan([
        {
          'day': 1,
          'readings': ['Genesis 1'],
        },
      ]);

      await coordinator.creditPlanDay(uid: uid, planId: 'p1', day: 99);

      expect((await laps.fetch(uid)).oldTestament, isEmpty);
    });

    test('a missing plan is survivable', () async {
      await coordinator.creditPlanDay(uid: uid, planId: 'nope', day: 1);
      expect((await laps.fetch(uid)).oldTestament, isEmpty);
    });

    test('solo plan reading alone can complete a testament', () async {
      await savePlan([
        {
          'day': 1,
          'readings': allChaptersOf(ReferenceParser.allBooks.sublist(39)),
        },
      ]);

      await coordinator.creditPlanDay(uid: uid, planId: 'p1', day: 1);

      final counts =
          ReadThroughService.countsFrom(await readThroughs.fetchAll(uid));
      expect(counts.newTestament, 1,
          reason: 'personal plans count toward read-throughs, which lifetime '
              'coverage never did');
    });
  });
}
