import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/badge_award.dart';
import 'package:bible_read/models/read_through.dart';
import 'package:bible_read/services/badge_service.dart';
import 'package:bible_read/services/milestone_announcer.dart';
import 'package:bible_read/services/read_through_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  const uid = 'alice';

  setUp(() => firestore = FakeFirebaseFirestore());

  group('BadgeService', () {
    late BadgeService badges;
    setUp(() => badges = BadgeService(firestore: firestore));

    Future<Set<String>> held() async => (await firestore
            .collection('users')
            .doc(uid)
            .collection('achievements')
            .get())
        .docs
        .map((d) => d.id)
        .toSet();

    test('awards nothing at zero', () async {
      final awarded = await badges.awardFor(uid, ReadThroughCounts.empty);
      expect(awarded, isEmpty);
      expect(await held(), isEmpty);
    });

    test('a first testament earns its badge only', () async {
      await badges.awardFor(
        uid,
        const ReadThroughCounts(oldTestament: 0, newTestament: 1),
      );
      expect(await held(), {'first_nt'});
    });

    test('a first whole Bible earns all three landmarks', () async {
      await badges.awardFor(
        uid,
        const ReadThroughCounts(oldTestament: 1, newTestament: 1),
      );
      expect(await held(), {'first_bible', 'first_ot', 'first_nt'});
    });

    test('tiers unlock at five and ten whole Bibles', () async {
      await badges.awardFor(
        uid,
        const ReadThroughCounts(oldTestament: 5, newTestament: 6),
      );
      expect(await held(), contains('bible_5'));
      expect(await held(), isNot(contains('bible_10')));

      await badges.awardFor(
        uid,
        const ReadThroughCounts(oldTestament: 10, newTestament: 12),
      );
      expect(await held(), contains('bible_10'));
    });

    test('re-awarding leaves the original unlock date alone', () async {
      await badges.awardFor(
        uid,
        const ReadThroughCounts(oldTestament: 0, newTestament: 1),
      );
      final again = await badges.awardFor(
        uid,
        const ReadThroughCounts(oldTestament: 0, newTestament: 2),
      );
      expect(again, isEmpty, reason: 'a badge already held is not re-awarded');
    });

    test('badges are never lost when a count falls', () async {
      await badges.awardFor(
        uid,
        const ReadThroughCounts(oldTestament: 1, newTestament: 1),
      );
      await badges.awardFor(uid, ReadThroughCounts.empty);
      expect(await held(), contains('first_bible'));
    });

    test('recording a read-through awards its badge', () async {
      final service = ReadThroughService(firestore: firestore);
      await service.recordDetected(
        uid: uid,
        scope: ReadThroughScope.newTestament,
        completedAt: DateTime(2026, 9, 5),
      );
      expect(await held(), contains('first_nt'));
    });
  });

  group('MilestoneAnnouncer', () {
    late MilestoneAnnouncer announcer;
    setUp(() => announcer = MilestoneAnnouncer(firestore: firestore));

    Future<Map<String, dynamic>?> entry(String dateKey) async => (await firestore
            .collection('read_logs')
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

    test('a detected testament is announced on that day', () async {
      await announcer.announce(
        uid: uid,
        completed: [row(ReadThroughScope.newTestament,
            ReadThroughSource.detected, lap: 3)],
        now: DateTime(2026, 9, 5),
      );

      final data = await entry('2026-09-05');
      expect(data?['milestone'], {'scope': 'nt', 'lapNumber': 3});
      expect(data?['uid'], uid);
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

      final milestone = (await entry('2026-09-05'))?['milestone'] as Map?;
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

      expect(await entry('2026-09-05'), isNull);
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

      expect(await entry('2026-09-05'), isNull);
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
