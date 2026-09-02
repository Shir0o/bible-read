// Covers the write-safety guarantees of the schedule batch paths.
//
// A long plan (whole Bible at one chapter a day is 1,189 days) exceeds
// Firestore's 500-writes-per-batch cap, so `updateScheduleBatch` must split its
// work across several commits. `FakeFirebaseFirestore` does not enforce that
// cap, so the chunking itself is asserted against a mock that counts commits;
// the fake is used to prove every day still lands.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/services/group_service.dart';

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockCollectionReference<T> extends Mock
    implements CollectionReference<T> {}

class MockDocumentReference<T> extends Mock implements DocumentReference<T> {}

class MockWriteBatch extends Mock implements WriteBatch {}

/// Builds [count] consecutive daily schedule entries starting 2026-01-01.
List<GroupSchedule> _days(int count) {
  final start = DateTime(2026, 1, 1);
  return List.generate(
    count,
    (i) => GroupSchedule(
      date: start.add(Duration(days: i)),
      chapters: ['Genesis ${i + 1}'],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    const channel = MethodChannel('plugins.flutter.io/firebase_crashlytics');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return null;
    });
    await Firebase.initializeApp();
  });

  group('GroupService.dateId', () {
    test('zero-pads month and day', () {
      expect(GroupService.dateId(DateTime(2026, 1, 5)), '2026-01-05');
      expect(GroupService.dateId(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('updateScheduleBatch chunking', () {
    late MockFirebaseFirestore mockFs;
    late MockWriteBatch batch;

    setUp(() {
      mockFs = MockFirebaseFirestore();
      batch = MockWriteBatch();

      final groups = MockCollectionReference<Map<String, dynamic>>();
      final groupDoc = MockDocumentReference<Map<String, dynamic>>();
      final scheduleCol = MockCollectionReference<Map<String, dynamic>>();
      final docRef = MockDocumentReference<Map<String, dynamic>>();

      when(() => mockFs.collection(GroupCollections.groups)).thenReturn(groups);
      when(() => groups.doc('g1')).thenReturn(groupDoc);
      when(() => groupDoc.collection(GroupCollections.schedule))
          .thenReturn(scheduleCol);
      when(() => scheduleCol.doc(any())).thenReturn(docRef);
      when(() => mockFs.batch()).thenReturn(batch);
      when(() => batch.commit()).thenAnswer((_) async {});
    });

    test('commits once when under the batch limit', () async {
      final service = GroupService(firestore: mockFs);

      await service.updateScheduleBatch(groupId: 'g1', schedules: _days(120));

      verify(() => batch.commit()).called(1);
    });

    test('splits a 1000-day plan across three commits', () async {
      final service = GroupService(firestore: mockFs);

      await service.updateScheduleBatch(groupId: 'g1', schedules: _days(1000));

      // 450 + 450 + 100 — every chunk stays under Firestore's 500 cap.
      verify(() => batch.commit()).called(3);
    });

    test('commits nothing for an empty schedule', () async {
      final service = GroupService(firestore: mockFs);

      await service.updateScheduleBatch(groupId: 'g1', schedules: const []);

      verifyNever(() => batch.commit());
    });
  });

  group('updateScheduleBatch persistence', () {
    late FakeFirebaseFirestore firestore;
    late GroupService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = GroupService(firestore: firestore);
    });

    test('writes every day of a 1200-day plan', () async {
      await service.updateScheduleBatch(groupId: 'g1', schedules: _days(1200));

      final snap = await firestore
          .collection(GroupCollections.groups)
          .doc('g1')
          .collection(GroupCollections.schedule)
          .get();

      expect(snap.docs.length, 1200);
    });

    test('writes the GroupSchedule.toFirestore shape under a padded id',
        () async {
      final day = GroupSchedule(
        date: DateTime(2026, 3, 7),
        chapters: const ['Jeremiah 1', 'Jeremiah 2'],
      );

      await service.updateScheduleBatch(groupId: 'g1', schedules: [day]);

      final doc = await firestore
          .collection(GroupCollections.groups)
          .doc('g1')
          .collection(GroupCollections.schedule)
          .doc('2026-03-07')
          .get();

      expect(doc.exists, isTrue);
      expect(doc.data(), day.toFirestore());
    });
  });

  group('deleteScheduleDays', () {
    late FakeFirebaseFirestore firestore;
    late GroupService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = GroupService(firestore: firestore);
    });

    test('removes only the named days', () async {
      await service.updateScheduleBatch(groupId: 'g1', schedules: _days(5));

      await service.deleteScheduleDays(
        groupId: 'g1',
        dates: [DateTime(2026, 1, 2), DateTime(2026, 1, 4)],
      );

      final snap = await firestore
          .collection(GroupCollections.groups)
          .doc('g1')
          .collection(GroupCollections.schedule)
          .get();

      expect(
        snap.docs.map((d) => d.id).toList()..sort(),
        ['2026-01-01', '2026-01-03', '2026-01-05'],
      );
    });

    test('tolerates an empty date list', () async {
      await service.updateScheduleBatch(groupId: 'g1', schedules: _days(3));

      await service.deleteScheduleDays(groupId: 'g1', dates: const []);

      final snap = await firestore
          .collection(GroupCollections.groups)
          .doc('g1')
          .collection(GroupCollections.schedule)
          .get();

      expect(snap.docs.length, 3);
    });
  });
}
