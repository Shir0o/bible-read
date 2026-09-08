import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/badge_award.dart';
import 'package:bible_read/models/read_through.dart';
import 'package:bible_read/services/milestone_announcer.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  const uid = 'alice';

  setUp(() => firestore = FakeFirebaseFirestore());

  group('MilestoneAnnouncer', () {
    late MilestoneAnnouncer announcer;

    setUp(() {
      announcer = MilestoneAnnouncer(
        firestore: firestore,
        // Membership is resolved by the real path in production; the tests
        // pin the Group list so each case states exactly what it asserts on.
        groupIdsResolver: () => const ['g1', 'g2'],
      );
    });

    Future<Map<String, dynamic>?> groupEntry(
      String groupId,
      String dateKey,
    ) async =>
        (await firestore
                .collection('groups')
                .doc(groupId)
                .collection('read_log')
                .doc(dateKey)
                .collection('entries')
                .doc(uid)
                .get())
            .data();

    ReadThrough row(
      ReadThroughScope scope,
      ReadThroughSource source, {
      int lap = 1,
    }) =>
        ReadThrough(
          id: '${scope.id}_$lap',
          scope: scope,
          completedAt: DateTime(2026, 9, 5),
          source: source,
          lapNumber: lap,
        );

    test('a detected testament is announced on that day, in every Group', () async {
      await announcer.announce(
        uid: uid,
        completed: [row(ReadThroughScope.newTestament,
            ReadThroughSource.detected, lap: 3)],
        now: DateTime(2026, 9, 5),
      );

      for (final groupId in const ['g1', 'g2']) {
        final data = await groupEntry(groupId, '2026-09-05');
        expect(data?['milestone'], {'scope': 'nt', 'lapNumber': 3});
        expect(data?['uid'], uid);
      }
    });

    test('a whole Bible closed at the same time rides along', () async {
      await announcer.announce(
        uid: uid,
        completed: [
          row(ReadThroughScope.newTestament, ReadThroughSource.detected,
              lap: 3),
          row(ReadThroughScope.wholeBible, ReadThroughSource.derived, lap: 2),
        ],
        now: DateTime(2026, 9, 5),
      );

      final milestone =
          (await groupEntry('g1', '2026-09-05'))?['milestone'] as Map?;
      expect(milestone?['wholeBibleLap'], 2);
    });

    test('backfilled records are never announced', () async {
      await announcer.announce(
        uid: uid,
        completed: [
          row(ReadThroughScope.oldTestament, ReadThroughSource.backfilled),
        ],
        now: DateTime(2026, 9, 5),
      );

      expect(await groupEntry('g1', '2026-09-05'), isNull);
      expect(await groupEntry('g2', '2026-09-05'), isNull);
    });

    test('migrated records are never announced', () async {
      await announcer.announce(
        uid: uid,
        completed: [
          row(ReadThroughScope.oldTestament, ReadThroughSource.migrated),
          row(ReadThroughScope.wholeBible, ReadThroughSource.derived),
        ],
        now: DateTime(2026, 9, 5),
      );

      expect(await groupEntry('g1', '2026-09-05'), isNull);
      expect(await groupEntry('g2', '2026-09-05'), isNull);
    });

    test('a reader with no Groups announces nothing and nothing errors', () async {
      final solo = MilestoneAnnouncer(
        firestore: firestore,
        groupIdsResolver: () => const [],
      );
      await solo.announce(
        uid: uid,
        completed: [
          row(ReadThroughScope.newTestament, ReadThroughSource.detected,
              lap: 1),
        ],
        now: DateTime(2026, 9, 5),
      );

      expect((await firestore.collectionGroup('read_log').get()).docs,
          isEmpty);
    });
  });
  group('FeedMilestone copy', () {
    test('names the testament and the pairing', () {
      const milestone = FeedMilestone(
        scope: ReadThroughScope.newTestament,
        lapNumber: 3,
        wholeBibleLap: 2,
      );
      expect(milestone.headline, 'Finished the New Testament');
      expect(milestone.detail, '3rd time through · and a 2nd whole Bible');
    });

    test('omits the pairing when there is none', () {
      const milestone = FeedMilestone(
        scope: ReadThroughScope.oldTestament,
        lapNumber: 1,
      );
      expect(milestone.detail, '1st time through');
    });

    test('unreadable milestone data is simply absent', () {
      expect(FeedMilestone.fromMap(null), isNull);
      expect(FeedMilestone.fromMap('nonsense'), isNull);
      expect(FeedMilestone.fromMap({'lapNumber': 2}), isNull);
    });
  });

  group('BadgeDefinition', () {
    test('remaining counts down to the next landmark', () {
      const counts = ReadThroughCounts(oldTestament: 3, newTestament: 4);
      final five =
          BadgeDefinition.all.firstWhere((b) => b.id == 'bible_5');
      expect(counts.wholeBible, 3);
      expect(five.remainingFor(counts), 2);
    });
  });
}
