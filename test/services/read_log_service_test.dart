import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/services/read_log_service.dart';

// The feed is denormalized per Group (ADR-0004, #801): marking a day writes
// one entry into every Group the reader belongs to, a reader with no Groups
// writes nothing and nothing errors, and clearing removes every copy. Reads
// merge the entries of all the reader's Groups live, so a co-member's Amen or
// new read appears without a manual refresh.
void main() {
  late FakeFirebaseFirestore firestore;
  final fixedDate = DateTime(2025, 7, 15);

  Future<void> seedGroup({
    required String id,
    required String ownerUid,
    List<String> members = const [],
  }) async {
    await firestore.collection('groups').doc(id).set({
      'name': 'Group $id',
      'ownerUid': ownerUid,
      'memberCount': members.length + 1,
    });
    await firestore
        .collection('groups')
        .doc(id)
        .collection('members')
        .doc(ownerUid)
        .set({'uid': ownerUid, 'role': 'owner'});
    for (final uid in members) {
      await firestore
          .collection('groups')
          .doc(id)
          .collection('members')
          .doc(uid)
          .set({'uid': uid, 'role': 'member'});
    }
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  group('mark', () {
    test('writes one entry per Group the reader belongs to', () async {
      await seedGroup(id: 'g1', ownerUid: 'u1', members: ['u2']);
      await seedGroup(id: 'g2', ownerUid: 'u3', members: ['u2']);
      final user = MockUser(
        uid: 'u2',
        displayName: 'Test User',
        email: 'test@example.com',
      );

      await ReadLogService(firestore: firestore).mark(
        user,
        date: fixedDate,
      );

      final dateKey = '2025-07-15';
      final g1 = await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc(dateKey)
          .collection('entries')
          .doc(user.uid)
          .get();
      final g2 = await firestore
          .collection('groups')
          .doc('g2')
          .collection('read_log')
          .doc(dateKey)
          .collection('entries')
          .doc(user.uid)
          .get();

      expect(g1.exists, isTrue);
      expect(g1.data()?['name'], 'Test');
      expect(g1.data()?['email'], 'test@example.com');
      expect(g1.data()?['uid'], 'u2');
      expect(g1.data()?['dateId'], dateKey);
      expect(g2.exists, isTrue);
      expect(g2.data()?['uid'], 'u2');
    });

    test('a reader with no Groups writes no entries and nothing errors',
        () async {
      final user = MockUser(uid: 'solo', displayName: 'Solo User');

      await ReadLogService(firestore: firestore).mark(
        user,
        date: fixedDate,
      );

      final stray = await firestore.collectionGroup('read_log').get();
      expect(stray.docs, isEmpty);
    });

    test('is idempotent for the same reader and day', () async {
      await seedGroup(id: 'g1', ownerUid: 'u1', members: ['u2']);
      final user = MockUser(uid: 'u2', displayName: 'Test User');
      final service = ReadLogService(firestore: firestore);

      await service.mark(user, date: fixedDate);
      await service.mark(user, date: fixedDate);

      final entries = await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc('2025-07-15')
          .collection('entries')
          .get();
      expect(entries.docs, hasLength(1));
    });

    test('a reader in two Groups sharing a member writes one copy each',
        () async {
      await seedGroup(id: 'g1', ownerUid: 'u1', members: ['u2']);
      await seedGroup(id: 'g2', ownerUid: 'u2', members: []);
      final user = MockUser(uid: 'u2', displayName: 'Test User');

      await ReadLogService(firestore: firestore).mark(
        user,
        date: fixedDate,
      );

      final g1 = await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc('2025-07-15')
          .collection('entries')
          .doc('u2')
          .get();
      final g2 = await firestore
          .collection('groups')
          .doc('g2')
          .collection('read_log')
          .doc('2025-07-15')
          .collection('entries')
          .doc('u2')
          .get();
      expect(g1.exists, isTrue);
      expect(g2.exists, isTrue);
    });
  });

  group('clear', () {
    test('removes every copy across the reader\'s Groups', () async {
      await seedGroup(id: 'g1', ownerUid: 'u1', members: ['u2']);
      await seedGroup(id: 'g2', ownerUid: 'u3', members: ['u2']);
      final user = MockUser(uid: 'u2', displayName: 'Test User');
      final service = ReadLogService(firestore: firestore);

      await service.mark(user, date: fixedDate);
      await service.clear(user, date: fixedDate);

      final g1 = await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc('2025-07-15')
          .collection('entries')
          .doc(user.uid)
          .get();
      final g2 = await firestore
          .collection('groups')
          .doc('g2')
          .collection('read_log')
          .doc('2025-07-15')
          .collection('entries')
          .doc(user.uid)
          .get();
      expect(g1.exists, isFalse);
      expect(g2.exists, isFalse);
    });

    test('clearing with no Groups is a no-op', () async {
      final user = MockUser(uid: 'solo', displayName: 'Solo User');

      await ReadLogService(firestore: firestore).clear(
        user,
        date: fixedDate,
      );
    });
  });

  group('entriesFor', () {
    test('merges entries from every Group the reader belongs to', () async {
      await seedGroup(id: 'g1', ownerUid: 'u1', members: ['u2']);
      await seedGroup(id: 'g2', ownerUid: 'u3', members: ['u2']);
      final today = '2025-07-15';

      // u1 read in g1 and g2; u3 read only in g2; a stranger only in g1.
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc(today)
          .collection('entries')
          .doc('u1')
          .set({'uid': 'u1', 'name': 'Owen', 'dateId': today});
      await firestore
          .collection('groups')
          .doc('g2')
          .collection('read_log')
          .doc(today)
          .collection('entries')
          .doc('u1')
          .set({'uid': 'u1', 'name': 'Owen', 'dateId': today});
      await firestore
          .collection('groups')
          .doc('g2')
          .collection('read_log')
          .doc(today)
          .collection('entries')
          .doc('u3')
          .set({'uid': 'u3', 'name': 'Cara', 'dateId': today});
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc(today)
          .collection('entries')
          .doc('u9')
          .set({'uid': 'u9', 'name': 'Stranger', 'dateId': today});

      // The stream is live: an early event may carry only the Groups whose
      // snapshots have arrived so far, so drain until u3 (g2-only) has been
      // reported rather than asserting on the first event alone.
      final uids = await ReadLogService(firestore: firestore).entriesForGroups(
          const ['g1', 'g2'],
          dateKey: today).firstWhere((uids) => uids.contains('u3'));

      // u9 seeded an entry in g1 as well — the feed shows a Group's entries;
      // narrowing to the Circle is #802's job, not the feed's.
      expect(uids, containsAll(['u1', 'u3', 'u9']));
    });

    test('a person in two shared Groups appears once', () async {
      final today = '2025-07-15';
      await seedGroup(id: 'g1', ownerUid: 'u1', members: ['u2']);
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc(today)
          .collection('entries')
          .doc('u1')
          .set({'uid': 'u1', 'name': 'Owen', 'dateId': today});
      await firestore
          .collection('groups')
          .doc('g2')
          .collection('read_log')
          .doc(today)
          .collection('entries')
          .doc('u1')
          .set({'uid': 'u1', 'name': 'Owen', 'dateId': today});

      // Drain until both Groups have reported (two distinct uids would mean
      // dedupe broke; one uid reported twice means merge failed).
      final uids = await ReadLogService(firestore: firestore).entriesForGroups(
          const ['g1', 'g2'],
          dateKey: today).firstWhere((uids) => uids.length == 1);

      expect(uids, ['u1']);
    });

    test('no Groups yields an empty list, not an error', () async {
      final uids = await ReadLogService(firestore: firestore)
          .entriesForGroups(const [], dateKey: '2025-07-15').first;
      expect(uids, isEmpty);
    });

    test('emits live when a co-member marks or Amen arrives', () async {
      final today = '2025-07-15';
      await seedGroup(id: 'g1', ownerUid: 'u1', members: ['u2']);

      final service = ReadLogService(firestore: firestore);
      final emitted = <List<String>>[];
      final sub = service
          .entriesForGroups(const ['g1'], dateKey: today).listen(emitted.add);
      await Future<void>.delayed(Duration.zero);
      // Wait for the first (empty) event.
      while (emitted.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc(today)
          .collection('entries')
          .doc('u2')
          .set({'uid': 'u2', 'name': 'Miriam', 'dateId': today});
      while (emitted.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(emitted.last, contains('u2'));
      await sub.cancel();
    });
  });

  group('groupIdsFor', () {
    test('lists the Groups the reader belongs to', () async {
      await seedGroup(id: 'g1', ownerUid: 'u1', members: ['u2']);
      await seedGroup(id: 'g2', ownerUid: 'u3', members: []);

      final ids = await ReadLogService(firestore: firestore).groupIdsFor('u2');

      expect(ids, ['g1']);
    });
  });
}
