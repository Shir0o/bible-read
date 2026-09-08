import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:bible_read/services/reflection_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ReflectionService service;
  const uid = 'test-user';
  const dateKey = '2026-07-16';

  /// Seeds [uid] as a member of Groups [ids], so shared copies fan out to
  /// `groups/{id}/read_log/{date}/entries/{uid}` exactly as the app does.
  Future<void> seedMembership(List<String> ids) async {
    for (final id in ids) {
      await firestore.collection('groups').doc(id).set({'name': 'Group $id'});
      await firestore
          .collection('groups')
          .doc(id)
          .collection('members')
          .doc(uid)
          .set({'uid': uid, 'role': 'member'});
    }
  }

  Future<Map<String, dynamic>?> entryIn(String groupId) async => firestore
      .collection('groups')
      .doc(groupId)
      .collection('read_log')
      .doc(dateKey)
      .collection('entries')
      .doc(uid)
      .get()
      .then((d) => d.data());

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = ReflectionService(firestore: firestore);
  });

  test('fetchReflection returns null if no document exists', () async {
    final reflection = await service.fetchReflection(uid, dateKey);
    expect(reflection, isNull);
  });

  test('saveReflection then fetchReflection round-trips the text', () async {
    await service.saveReflection(uid, dateKey, 'Dead to sin, alive to God.');

    final reflection = await service.fetchReflection(uid, dateKey);
    expect(reflection?.text, 'Dead to sin, alive to God.');
  });

  test('saveReflection trims surrounding whitespace', () async {
    await service.saveReflection(uid, dateKey, '  A single line.  ');

    final reflection = await service.fetchReflection(uid, dateKey);
    expect(reflection?.text, 'A single line.');
  });

  test(
    'saveReflection with blank text deletes any existing reflection',
    () async {
      await service.saveReflection(uid, dateKey, 'First draft');
      expect((await service.fetchReflection(uid, dateKey))?.text, isNotNull);

      await service.saveReflection(uid, dateKey, '   ');

      expect(await service.fetchReflection(uid, dateKey), isNull);
    },
  );

  test('deleteReflection removes a saved reflection', () async {
    await service.saveReflection(uid, dateKey, 'Something worth keeping');
    await service.deleteReflection(uid, dateKey);

    expect(await service.fetchReflection(uid, dateKey), isNull);
  });

  test('saveReflection overwrites a previous entry for the same day', () async {
    await service.saveReflection(uid, dateKey, 'First draft');
    await service.saveReflection(uid, dateKey, 'Revised thought');

    final reflection = await service.fetchReflection(uid, dateKey);
    expect(reflection?.text, 'Revised thought');
  });

  test('reflections for different days are independent', () async {
    await service.saveReflection(uid, '2026-07-15', 'Yesterday');
    await service.saveReflection(uid, '2026-07-16', 'Today');

    expect(
      (await service.fetchReflection(uid, '2026-07-15'))?.text,
      'Yesterday',
    );
    expect((await service.fetchReflection(uid, '2026-07-16'))?.text, 'Today');
  });

  group('sharing (#807)', () {
    test('saveReflection with share copies the text onto the read-log entry',
        () async {
      await seedMembership(['g1', 'g2']);

      await service.saveReflection(uid, dateKey, 'Worth saying aloud.',
          share: true);

      for (final groupId in ['g1', 'g2']) {
        final entry = await entryIn(groupId);
        expect(entry?['sharedReflection'], 'Worth saying aloud.',
            reason: 'copy present in $groupId');
      }
    });

    test('a reader with no Groups shares nothing and nothing errors', () async {
      await service.saveReflection(uid, dateKey, 'Just me today.', share: true);

      final stray = await firestore.collectionGroup('read_log').get();
      expect(stray.docs, isEmpty);
    });

    test(
        'unshare deletes the copied text from every entry, private original intact',
        () async {
      await seedMembership(['g1', 'g2']);
      await service.saveReflection(uid, dateKey, 'First shared.', share: true);

      await service.saveReflection(uid, dateKey, 'First shared.', share: false);

      for (final groupId in ['g1', 'g2']) {
        final entry = await entryIn(groupId);
        expect(entry?['sharedReflection'], isNull,
            reason: 'copy removed in $groupId');
      }
      final original = await service.fetchReflection(uid, dateKey);
      expect(original?.text, 'First shared.');
      expect(original?.shared, isFalse);
    });

    test('deleteReflection removes any shared copy with the private document',
        () async {
      await seedMembership(['g1']);
      await service.saveReflection(uid, dateKey, 'Shared then deleted.',
          share: true);

      await service.deleteReflection(uid, dateKey);

      final entry = await entryIn('g1');
      expect(entry?['sharedReflection'], isNull);
      expect(await service.fetchReflection(uid, dateKey), isNull);
    });

    test('editing a shared reflection updates the copy and stays shared',
        () async {
      await seedMembership(['g1']);
      await service.saveReflection(uid, dateKey, 'First draft.', share: true);

      await service.saveReflection(uid, dateKey, 'Revised thought.',
          share: true);

      final entry = await entryIn('g1');
      expect(entry?['sharedReflection'], 'Revised thought.');
      final original = await service.fetchReflection(uid, dateKey);
      expect(original?.shared, isTrue);
    });

    test('saving unshared never touches the Showing-up mark or its entry',
        () async {
      await seedMembership(['g1']);
      // The Showing-up mark exists before any reflection write.
      final entryRef = firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc(dateKey)
          .collection('entries')
          .doc(uid);
      await entryRef.set({
        'uid': uid,
        'dateId': dateKey,
        'timestamp': Timestamp.fromDate(DateTime(2026, 7, 16, 7)),
      });
      final before = await entryRef.get();

      await service.saveReflection(uid, dateKey, 'Private words.');
      await service.saveReflection(uid, dateKey, 'Private words.', share: true);
      await service.saveReflection(uid, dateKey, 'Revised.', share: true);
      await service.saveReflection(uid, dateKey, 'Revised.', share: false);

      // Every field the mark owns is exactly as it was; the reflection
      // writes only ever touch sharedReflection.
      final after = await entryRef.get();
      expect(
        after.data()?['timestamp'],
        before.data()?['timestamp'],
      );
      expect(after.data()?['dateId'], before.data()?['dateId']);
      expect(after.data()?['sharedReflection'], isNull);
    });
  });

  group('migration (#807)', () {
    test('pre-migration documents (no shared field) read as unshared',
        () async {
      // A fixture exactly as ReflectionService wrote it before sharing
      // existed: text and updatedAt only. The absence of the field means
      // unshared — every existing Reflection stays private.
      await firestore
          .collection('users')
          .doc(uid)
          .collection('reflections')
          .doc(dateKey)
          .set({
        'text': 'Written before sharing existed.',
        'updatedAt': Timestamp.fromDate(DateTime(2026, 7, 16, 8)),
      });

      final reflection = await service.fetchReflection(uid, dateKey);
      expect(reflection, isNotNull);
      expect(reflection!.shared, isFalse);
    });
  });
}
