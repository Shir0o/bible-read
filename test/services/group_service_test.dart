import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:bible_read/services/group_service.dart';

class MockCrashlytics extends Mock implements FirebaseCrashlytics {}

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockCollectionReference<T> extends Mock
    implements CollectionReference<T> {}

class MockDocumentReference<T> extends Mock implements DocumentReference<T> {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('GroupService', () {
    late FakeFirebaseFirestore firestore;
    late GroupService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = GroupService(firestore: firestore);
    });

    test('createGroup creates group and owner member', () async {
      final id = await service.createGroup(ownerUid: 'u1', name: 'Test');

      final doc =
          await firestore.collection(GroupCollections.groups).doc(id).get();
      expect(doc.exists, isTrue);
      expect(doc.data()?['name'], 'Test');
      expect(doc.data()?['ownerUid'], 'u1');

      final member = await firestore
          .collection(GroupCollections.groups)
          .doc(id)
          .collection(GroupCollections.members)
          .doc('u1')
          .get();
      expect(member.exists, isTrue);
    });

    test('joinGroup adds membership document', () async {
      await firestore
          .collection(GroupCollections.groups)
          .doc('g1')
          .set({'name': 'G', 'ownerUid': 'u1'});

      await service.joinGroup(groupId: 'g1', uid: 'u2');

      final member = await firestore
          .collection(GroupCollections.groups)
          .doc('g1')
          .collection(GroupCollections.members)
          .doc('u2')
          .get();
      expect(member.exists, isTrue);
    });

    test('leaveGroup removes membership document', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      await groupRef.collection(GroupCollections.members).doc('u2').set({});

      await service.leaveGroup(groupId: 'g1', uid: 'u2');

      final member =
          await groupRef.collection(GroupCollections.members).doc('u2').get();
      expect(member.exists, isFalse);
    });

    test('updateSchedule writes schedule document', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      final schedule = GroupSchedule(
        date: DateTime(2024, 1, 1),
        chapters: const ['Gen 1'],
      );

      await service.updateSchedule(groupId: 'g1', schedule: schedule);

      final doc = await groupRef
          .collection(GroupCollections.schedule)
          .doc('2024-01-01')
          .get();
      expect(doc.exists, isTrue);
      final stored = GroupSchedule.fromFirestore(doc);
      expect(stored.chapters, schedule.chapters);
      expect(stored.date.toUtc(), schedule.date.toUtc());
    });

    test('fetchTodaysChapters returns schedule for today', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      final now = DateTime.now().toUtc();
      final id =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await groupRef.collection(GroupCollections.schedule).doc(id).set({
        'date': Timestamp.fromDate(now),
        'chapters': ['John 1'],
      });

      final chapters = await service.fetchTodaysChapters('g1');
      expect(chapters, ['John 1']);

      final empty = await service.fetchTodaysChapters('missing');
      expect(empty, isEmpty);
    });

    test('groupsForUser streams groups where user is member', () async {
      final g1 = firestore.collection(GroupCollections.groups).doc('g1');
      await g1.set({'name': 'One', 'ownerUid': 'u1'});
      await g1.collection(GroupCollections.members).doc('u1').set({});
      final g2 = firestore.collection(GroupCollections.groups).doc('g2');
      await g2.set({'name': 'Two', 'ownerUid': 'u2'});
      await g2.collection(GroupCollections.members).doc('u1').set({});

      final groups = await service.groupsForUser('u1').first;
      final ids = groups.map((g) => g.id).toSet();
      expect(ids, {'g1', 'g2'});
    });

    test('memberNames streams display names', () async {
      await firestore.collection('users').doc('u1').set({'name': 'Alice'});
      await firestore.collection('users').doc('u2').set({'name': 'Bob'});
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      await groupRef.collection(GroupCollections.members).doc('u1').set({});
      await groupRef.collection(GroupCollections.members).doc('u2').set({});

      final names = await service.memberNames('g1').first;
      expect(names.toSet(), {'Alice', 'Bob'});
    });

    test('schedule streams list of entries', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      await groupRef
          .collection(GroupCollections.schedule)
          .doc('2024-01-01')
          .set({
        'date': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
        'chapters': ['Gen 1']
      });
      final entries = await service.schedule('g1').first;
      expect(entries, hasLength(1));
      expect(entries.first.chapters, ['Gen 1']);
    });

    test('fetchTodaysChapters logs and returns empty list on error', () async {
      final mockFs = MockFirebaseFirestore();
      final groups = MockCollectionReference<Map<String, dynamic>>();
      final groupDoc = MockDocumentReference<Map<String, dynamic>>();
      final schedule = MockCollectionReference<Map<String, dynamic>>();
      final scheduleDoc = MockDocumentReference<Map<String, dynamic>>();

      when(() => mockFs.collection(GroupCollections.groups)).thenReturn(groups);
      when(() => groups.doc('g1')).thenReturn(groupDoc);
      when(() => groupDoc.collection(GroupCollections.schedule))
          .thenReturn(schedule);
      when(() => schedule.doc(any())).thenReturn(scheduleDoc);
      when(() => scheduleDoc.get()).thenThrow(Exception('boom'));

      final crash = MockCrashlytics();
      ErrorLogger.crashlytics = crash;
      when(() => crash.recordError(any(), any(),
          reason: any(named: 'reason'),
          information: any(named: 'information'),
          printDetails: any(named: 'printDetails'),
          fatal: any(named: 'fatal'))).thenAnswer((_) async {});

      final svc = GroupService(firestore: mockFs);
      final chapters = await svc.fetchTodaysChapters('g1');
      expect(chapters, isEmpty);

      verify(() => crash.recordError(any(), any(),
          reason: null,
          information: any(named: 'information'),
          printDetails: any(named: 'printDetails'),
          fatal: false)).called(1);
    });

    test('leaveGroup rethrows and logs on error', () async {
      final mockFs = MockFirebaseFirestore();
      final groups = MockCollectionReference<Map<String, dynamic>>();
      final groupDoc = MockDocumentReference<Map<String, dynamic>>();
      final members = MockCollectionReference<Map<String, dynamic>>();
      final memberDoc = MockDocumentReference<Map<String, dynamic>>();

      when(() => mockFs.collection(GroupCollections.groups)).thenReturn(groups);
      when(() => groups.doc('g1')).thenReturn(groupDoc);
      when(() => groupDoc.collection(GroupCollections.members))
          .thenReturn(members);
      when(() => members.doc('u1')).thenReturn(memberDoc);
      when(() => memberDoc.delete()).thenThrow(Exception('fail'));

      final crash = MockCrashlytics();
      ErrorLogger.crashlytics = crash;
      when(() => crash.recordError(any(), any(),
          reason: any(named: 'reason'),
          information: any(named: 'information'),
          printDetails: any(named: 'printDetails'),
          fatal: any(named: 'fatal'))).thenAnswer((_) async {});

      final svc = GroupService(firestore: mockFs);

      await expectLater(
          svc.leaveGroup(groupId: 'g1', uid: 'u1'), throwsException);

      verify(() => crash.recordError(any(), any(),
          reason: null,
          information: any(named: 'information'),
          printDetails: any(named: 'printDetails'),
          fatal: false)).called(1);
    });
  });
}
