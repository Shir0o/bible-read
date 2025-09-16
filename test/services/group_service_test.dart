// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/models/notification_preferences.dart';
import 'package:bible_read/services/notification_service.dart'
    show NotificationCollections;

class MockCrashlytics extends Mock implements FirebaseCrashlytics {}

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockCollectionReference<T> extends Mock
    implements CollectionReference<T> {}

class MockDocumentReference<T> extends Mock implements DocumentReference<T> {}

class MockDocumentSnapshot<T> extends Mock implements DocumentSnapshot<T> {}

class MockQuery<T> extends Mock implements Query<T> {}

class MockQuerySnapshot<T> extends Mock implements QuerySnapshot<T> {}

class MockWriteBatch extends Mock implements WriteBatch {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(SetOptions(merge: true));
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
      expect(doc.data()?.containsKey('isPublic'), isFalse);

      final member = await firestore
          .collection(GroupCollections.groups)
          .doc(id)
          .collection(GroupCollections.members)
          .doc('u1')
          .get();
      expect(member.exists, isTrue);
      expect(member.data()?['uid'], 'u1');
      expect(member.data()?['role'], 'owner');
      expect(member.data()?['joinedAt'], isA<Timestamp>());
    });

    test('joinGroup creates join request and notification', () async {
      await firestore
          .collection(GroupCollections.groups)
          .doc('g1')
          .set({'name': 'G', 'ownerUid': 'u1'});

      await service.joinGroup(groupId: 'g1', uid: 'u2', name: 'User');

      final member = await firestore
          .collection(GroupCollections.groups)
          .doc('g1')
          .collection(GroupCollections.members)
          .doc('u2')
          .get();
      expect(member.exists, isFalse);

      final request = await firestore
          .collection(GroupCollections.groups)
          .doc('g1')
          .collection(GroupCollections.joinRequests)
          .doc('u2')
          .get();
      expect(request.exists, isTrue);
      expect(request.data()?['uid'], 'u2');
      expect(request.data()?['name'], 'User');
      expect(request.data()?['requestedAt'], isA<Timestamp>());

      final notifSnap = await firestore
          .collection(NotificationCollections.users)
          .doc('u1')
          .collection(NotificationCollections.notifications)
          .get();
      expect(notifSnap.docs.length, 1);
      final data = notifSnap.docs.first.data();
      expect(data['type'], NotificationType.groupJoinRequest.name);
      expect(data['fromUid'], 'u2');
      expect(data['senderUid'], 'u2');
    });

    test('approveJoinRequest moves member and removes request', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      await groupRef.collection(GroupCollections.joinRequests).doc('u2').set({
        'uid': 'u2',
        'name': 'User',
        'requestedAt': Timestamp.fromDate(DateTime.utc(2024)),
      });

      await service.approveJoinRequest(groupId: 'g1', uid: 'u2');

      final member =
          await groupRef.collection(GroupCollections.members).doc('u2').get();
      expect(member.exists, isTrue);
      expect(member.data()?['name'], 'User');
      final request = await groupRef
          .collection(GroupCollections.joinRequests)
          .doc('u2')
          .get();
      expect(request.exists, isFalse);
    });

    test('approveJoinRequest performs batched write', () async {
      final firestore = MockFirebaseFirestore();
      final service = GroupService(firestore: firestore);

      final groups = MockCollectionReference<Map<String, dynamic>>();
      final groupRef = MockDocumentReference<Map<String, dynamic>>();
      final joinRequests = MockCollectionReference<Map<String, dynamic>>();
      final members = MockCollectionReference<Map<String, dynamic>>();
      final requestRef = MockDocumentReference<Map<String, dynamic>>();
      final memberRef = MockDocumentReference<Map<String, dynamic>>();
      final requestSnap = MockDocumentSnapshot<Map<String, dynamic>>();
      final batch = MockWriteBatch();

      when(() => firestore.collection(GroupCollections.groups))
          .thenReturn(groups);
      when(() => groups.doc('g1')).thenReturn(groupRef);
      when(() => groupRef.collection(GroupCollections.joinRequests))
          .thenReturn(joinRequests);
      when(() => groupRef.collection(GroupCollections.members))
          .thenReturn(members);
      when(() => joinRequests.doc('u2')).thenReturn(requestRef);
      when(() => members.doc('u2')).thenReturn(memberRef);
      when(() => requestRef.get()).thenAnswer((_) async => requestSnap);
      when(() => requestSnap.data()).thenReturn({'name': 'User'});
      when(() => firestore.batch()).thenReturn(batch);
      when(() => batch.commit()).thenAnswer((_) async {});

      await service.approveJoinRequest(groupId: 'g1', uid: 'u2');

      verify(() => firestore.batch()).called(1);
      verify(() => batch.set(memberRef, any<Map<String, dynamic>>(), any()))
          .called(1);
      verify(() => batch.delete(requestRef)).called(1);
      verify(() => batch.commit()).called(1);
      verifyNever(() => memberRef.set(any(), any()));
      verifyNever(() => requestRef.delete());
    });

    test('denyJoinRequest removes request without adding member', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      await groupRef.collection(GroupCollections.joinRequests).doc('u2').set({
        'uid': 'u2',
        'name': 'User',
        'requestedAt': Timestamp.fromDate(DateTime.utc(2024)),
      });

      await service.denyJoinRequest(groupId: 'g1', uid: 'u2');

      final member =
          await groupRef.collection(GroupCollections.members).doc('u2').get();
      expect(member.exists, isFalse);
      final request = await groupRef
          .collection(GroupCollections.joinRequests)
          .doc('u2')
          .get();
      expect(request.exists, isFalse);
    });

    test('leaveGroup removes membership document', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      await groupRef.collection(GroupCollections.members).doc('u2').set({
        'uid': 'u2',
        'role': 'member',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024)),
      });

      await service.leaveGroup(groupId: 'g1', uid: 'u2');

      final member =
          await groupRef.collection(GroupCollections.members).doc('u2').get();
      expect(member.exists, isFalse);
    });

    test('promoteToAdmin updates member role to admin', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'owner'});
      await groupRef.collection(GroupCollections.members).doc('u2').set({
        'uid': 'u2',
        'role': 'member',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
      });

      await service.promoteToAdmin(
        groupId: 'g1',
        ownerUid: 'owner',
        uid: 'u2',
      );

      final member =
          await groupRef.collection(GroupCollections.members).doc('u2').get();
      expect(member.data()?['role'], 'admin');
    });

    test('demoteAdmin downgrades admin role to member', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'owner'});
      await groupRef.collection(GroupCollections.members).doc('u2').set({
        'uid': 'u2',
        'role': 'admin',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 2)),
      });

      await service.demoteAdmin(
        groupId: 'g1',
        ownerUid: 'owner',
        uid: 'u2',
      );

      final member =
          await groupRef.collection(GroupCollections.members).doc('u2').get();
      expect(member.data()?['role'], 'member');
    });

    test('role changes require owner permissions', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'owner'});
      await groupRef.collection(GroupCollections.members).doc('u2').set({
        'uid': 'u2',
        'role': 'member',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 3)),
      });
      await groupRef.collection(GroupCollections.members).doc('u3').set({
        'uid': 'u3',
        'role': 'admin',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 4)),
      });

      await expectLater(
        service.promoteToAdmin(groupId: 'g1', ownerUid: 'intruder', uid: 'u2'),
        throwsStateError,
      );
      await expectLater(
        service.demoteAdmin(groupId: 'g1', ownerUid: 'intruder', uid: 'u3'),
        throwsStateError,
      );

      final member =
          await groupRef.collection(GroupCollections.members).doc('u2').get();
      final admin =
          await groupRef.collection(GroupCollections.members).doc('u3').get();
      expect(member.data()?['role'], 'member');
      expect(admin.data()?['role'], 'admin');
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
      expect(stored.date, schedule.date);
      expect((doc.data()?['date'] as Timestamp).toDate(),
          DateTime.utc(2024, 1, 1).toLocal());
    });

    test('updateSchedule notifies group members', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      await groupRef
          .collection(GroupCollections.members)
          .doc('u1')
          .set({'uid': 'u1'});
      await groupRef
          .collection(GroupCollections.members)
          .doc('u2')
          .set({'uid': 'u2'});
      final schedule = GroupSchedule(
        date: DateTime(2024, 1, 1),
        chapters: const ['Gen 1'],
      );

      await service.updateSchedule(groupId: 'g1', schedule: schedule);

      final notif1 = await firestore
          .collection(NotificationCollections.users)
          .doc('u1')
          .collection(NotificationCollections.notifications)
          .get();
      final notif2 = await firestore
          .collection(NotificationCollections.users)
          .doc('u2')
          .collection(NotificationCollections.notifications)
          .get();

      expect(notif1.docs.single.data()['type'],
          NotificationType.groupScheduleUpdate.name);
      expect(notif2.docs.single.data()['type'],
          NotificationType.groupScheduleUpdate.name);
    });

    test('fetchTodaysChapters returns schedule for today', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      final now = DateTime.now();
      final id =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await groupRef.collection(GroupCollections.schedule).doc(id).set({
        'date': Timestamp.fromDate(DateTime.utc(now.year, now.month, now.day)),
        'chapters': ['John 1'],
      });

      final chapters = await service.fetchTodaysChapters('g1');
      expect(chapters, ['John 1']);

      final empty = await service.fetchTodaysChapters('missing');
      expect(empty, isEmpty);
    });

    test('fetchTodaysChapters handles positive UTC offset', () async {
      final offset = DateTime.now().timeZoneOffset;
      if (offset <= Duration.zero) {
        return;
      }
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      final now = DateTime.now();
      final id =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await groupRef.collection(GroupCollections.schedule).doc(id).set({
        'date': Timestamp.fromDate(DateTime.utc(now.year, now.month, now.day)),
        'chapters': ['John 1'],
      });
      final chapters = await service.fetchTodaysChapters('g1');
      expect(chapters, ['John 1']);
    });

    test('allGroups streams every group', () async {
      final g1 = firestore.collection(GroupCollections.groups).doc('g1');
      await g1.set({'name': 'One', 'ownerUid': 'u1'});
      final g2 = firestore.collection(GroupCollections.groups).doc('g2');
      await g2.set({'name': 'Two', 'ownerUid': 'u2'});
      final g3 = firestore.collection(GroupCollections.groups).doc('g3');
      await g3.set({'name': 'Three', 'ownerUid': 'u3'});

      final groups = await service.allGroups().firstWhere((g) => g.length == 3);
      final ids = groups.map((g) => g.id).toSet();
      expect(ids, {'g1', 'g2', 'g3'});
    });

    test('groupsForUser streams groups where user is member', () async {
      final g1 = firestore.collection(GroupCollections.groups).doc('g1');
      await g1.set({'name': 'One', 'ownerUid': 'u1'});
      await g1.collection(GroupCollections.members).doc('m1').set({
        'uid': 'u1',
        'role': 'member',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
      });
      final g2 = firestore.collection(GroupCollections.groups).doc('g2');
      await g2.set({'name': 'Two', 'ownerUid': 'u2'});
      await g2.collection(GroupCollections.members).doc('m2').set({
        'uid': 'u1',
        'role': 'member',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 2)),
      });
      final g3 = firestore.collection(GroupCollections.groups).doc('g3');
      await g3.set({'name': 'Three', 'ownerUid': 'u3'});
      await g3.collection(GroupCollections.members).doc('m3').set({
        'uid': 'u3',
        'role': 'member',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 3)),
      });

      final groups =
          await service.groupsForUser('u1').firstWhere((g) => g.length == 2);
      final ids = groups.map((g) => g.id).toSet();
      expect(ids, {'g1', 'g2'});
    });

    test('groupsForUser includes owned groups without membership doc',
        () async {
      final owned = firestore.collection(GroupCollections.groups).doc('g1');
      await owned.set({'name': 'G', 'ownerUid': 'u1'});

      final groups =
          await service.groupsForUser('u1').firstWhere((g) => g.isNotEmpty);
      expect(groups.map((g) => g.id), ['g1']);
    });

    test('groupsForUser returns owned group without owner membership doc',
        () async {
      final owned = firestore.collection(GroupCollections.groups).doc('g1');
      await owned.set({'name': 'G', 'ownerUid': 'u1'});
      await owned.collection(GroupCollections.members).doc('m2').set({
        'uid': 'u2',
        'role': 'member',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 2)),
      });

      final groups =
          await service.groupsForUser('u1').firstWhere((g) => g.isNotEmpty);
      expect(groups.map((g) => g.id), ['g1']);
    });

    test('groupsForUser deduplicates owned membership groups', () async {
      final owned = firestore.collection(GroupCollections.groups).doc('g1');
      await owned.set({'name': 'G', 'ownerUid': 'u1'});
      await owned.collection(GroupCollections.members).doc('m1').set({
        'uid': 'u1',
        'role': 'owner',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
      });

      final groups =
          await service.groupsForUser('u1').firstWhere((g) => g.isNotEmpty);
      expect(groups, hasLength(1));
      expect(groups.first.id, 'g1');
    });

    test('memberNames streams display names', () async {
      await firestore.collection('users').doc('u1').set({'name': 'Alice'});
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      await groupRef.collection(GroupCollections.members).doc('m1').set({
        'uid': 'u1',
        'role': 'owner',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
      });
      await groupRef.collection(GroupCollections.members).doc('m2').set({
        'uid': 'u2',
        'name': 'Bob',
        'role': 'member',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 2)),
      });
      await groupRef.collection(GroupCollections.members).doc('m3').set({
        'role': 'member',
      });

      final names = await service.memberNames('g1').first;
      expect(names.toSet(), {'Alice', 'Bob'});
    });

    test('memberNames batches user lookups', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      final expected = <String>{};
      for (var i = 0; i < 12; i++) {
        final uid = 'u\$i';
        final name = 'User \$i';
        await firestore.collection('users').doc(uid).set({'name': name});
        await groupRef.collection(GroupCollections.members).doc('m\$i').set({
          'uid': uid,
          'role': 'member',
          'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, i + 1)),
        });
        expected.add(name);
      }

      final names = await service.memberNames('g1').first;
      expect(names.toSet(), expected);
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

    test('groupsForUser logs and returns empty list on stream error', () async {
      final mockFs = MockFirebaseFirestore();
      final memberQuery = MockQuery<Map<String, dynamic>>();
      final groups = MockCollectionReference<Map<String, dynamic>>();
      final ownerQuery = MockQuery<Map<String, dynamic>>();
      final ownerSnap = MockQuerySnapshot<Map<String, dynamic>>();
      final err = Exception('fail');

      when(() => mockFs.collectionGroup(GroupCollections.members))
          .thenReturn(memberQuery);
      when(() => memberQuery.where('uid', isEqualTo: 'u1'))
          .thenReturn(memberQuery);
      when(() => memberQuery.snapshots()).thenAnswer((_) {
        final controller =
            StreamController<QuerySnapshot<Map<String, dynamic>>>();
        Future.microtask(() {
          controller.addError(err);
          controller.close();
        });
        return controller.stream;
      });

      when(() => mockFs.collection(GroupCollections.groups)).thenReturn(groups);
      when(() => groups.where('ownerUid', isEqualTo: 'u1'))
          .thenReturn(ownerQuery);
      when(() => ownerQuery.snapshots())
          .thenAnswer((_) => Stream.value(ownerSnap));
      when(() => ownerSnap.docs).thenReturn([]);

      final crash = MockCrashlytics();
      ErrorLogger.crashlytics = crash;
      when(() => crash.recordError(any(), any(),
          reason: any(named: 'reason'),
          information: any(named: 'information'),
          printDetails: any(named: 'printDetails'),
          fatal: any(named: 'fatal'))).thenAnswer((_) async {});

      final svc = GroupService(firestore: mockFs);
      await expectLater(svc.groupsForUser('u1'), emits(isEmpty));

      verify(() => crash.recordError(err, any(),
          reason: null,
          information: any(named: 'information'),
          printDetails: any(named: 'printDetails'),
          fatal: false)).called(1);
    });

    test('allGroups logs and returns empty list on stream error', () async {
      final mockFs = MockFirebaseFirestore();
      final groups = MockCollectionReference<Map<String, dynamic>>();
      final err = Exception('fail');

      when(() => mockFs.collection(GroupCollections.groups)).thenReturn(groups);
      when(() => groups.snapshots()).thenAnswer(
          (_) => Stream<QuerySnapshot<Map<String, dynamic>>>.error(err));

      final crash = MockCrashlytics();
      ErrorLogger.crashlytics = crash;
      when(() => crash.recordError(any(), any(),
          reason: any(named: 'reason'),
          information: any(named: 'information'),
          printDetails: any(named: 'printDetails'),
          fatal: any(named: 'fatal'))).thenAnswer((_) async {});

      final svc = GroupService(firestore: mockFs);
      await expectLater(svc.allGroups(), emits(isEmpty));

      verify(() => crash.recordError(err, any(),
          reason: null,
          information: any(named: 'information'),
          printDetails: any(named: 'printDetails'),
          fatal: false)).called(1);
    });

    test('memberNames surfaces stream errors', () async {
      final mockFs = MockFirebaseFirestore();
      final groups = MockCollectionReference<Map<String, dynamic>>();
      final groupDoc = MockDocumentReference<Map<String, dynamic>>();
      final members = MockCollectionReference<Map<String, dynamic>>();
      final err = Exception('fail');

      when(() => mockFs.collection(GroupCollections.groups)).thenReturn(groups);
      when(() => groups.doc('g1')).thenReturn(groupDoc);
      when(() => groupDoc.collection(GroupCollections.members))
          .thenReturn(members);
      when(() => members.snapshots()).thenAnswer(
          (_) => Stream<QuerySnapshot<Map<String, dynamic>>>.error(err));

      final crash = MockCrashlytics();
      ErrorLogger.crashlytics = crash;
      when(() => crash.recordError(any(), any(),
          reason: any(named: 'reason'),
          information: any(named: 'information'),
          printDetails: any(named: 'printDetails'),
          fatal: any(named: 'fatal'))).thenAnswer((_) async {});

      final svc = GroupService(firestore: mockFs);
      await expectLater(svc.memberNames('g1'), emitsError(same(err)));
    });

    test('schedule surfaces stream errors', () async {
      final mockFs = MockFirebaseFirestore();
      final groups = MockCollectionReference<Map<String, dynamic>>();
      final groupDoc = MockDocumentReference<Map<String, dynamic>>();
      final schedule = MockCollectionReference<Map<String, dynamic>>();
      final query = MockQuery<Map<String, dynamic>>();
      final err = Exception('fail');

      when(() => mockFs.collection(GroupCollections.groups)).thenReturn(groups);
      when(() => groups.doc('g1')).thenReturn(groupDoc);
      when(() => groupDoc.collection(GroupCollections.schedule))
          .thenReturn(schedule);
      when(() => schedule.orderBy('date')).thenReturn(query);
      when(() => query.snapshots()).thenAnswer(
          (_) => Stream<QuerySnapshot<Map<String, dynamic>>>.error(err));

      final crash = MockCrashlytics();
      ErrorLogger.crashlytics = crash;
      when(() => crash.recordError(any(), any(),
          reason: any(named: 'reason'),
          information: any(named: 'information'),
          printDetails: any(named: 'printDetails'),
          fatal: any(named: 'fatal'))).thenAnswer((_) async {});

      final svc = GroupService(firestore: mockFs);
      await expectLater(svc.schedule('g1'), emitsError(same(err)));
    });

    test('createGroup rethrows and logs on error', () async {
      final mockFs = MockFirebaseFirestore();
      final groups = MockCollectionReference<Map<String, dynamic>>();
      final groupDoc = MockDocumentReference<Map<String, dynamic>>();
      final err = Exception('fail');

      when(() => mockFs.collection(GroupCollections.groups)).thenReturn(groups);
      when(() => groups.doc()).thenReturn(groupDoc);
      when(() => groupDoc.set(any())).thenThrow(err);

      final crash = MockCrashlytics();
      ErrorLogger.crashlytics = crash;
      when(() => crash.recordError(any(), any(),
          reason: any(named: 'reason'),
          information: any(named: 'information'),
          printDetails: any(named: 'printDetails'),
          fatal: any(named: 'fatal'))).thenAnswer((_) async {});

      final svc = GroupService(firestore: mockFs);

      await expectLater(
          svc.createGroup(ownerUid: 'u1', name: 'G'), throwsA(same(err)));

      verify(() => crash.recordError(err, any(),
          reason: null,
          information: any(named: 'information'),
          printDetails: any(named: 'printDetails'),
          fatal: false)).called(1);
    });

    test('joinGroup rethrows and logs on error', () async {
      final mockFs = MockFirebaseFirestore();
      final groups = MockCollectionReference<Map<String, dynamic>>();
      final groupDoc = MockDocumentReference<Map<String, dynamic>>();
      final joinRequests = MockCollectionReference<Map<String, dynamic>>();
      final joinDoc = MockDocumentReference<Map<String, dynamic>>();
      final err = Exception('fail');

      when(() => mockFs.collection(GroupCollections.groups)).thenReturn(groups);
      when(() => groups.doc('g1')).thenReturn(groupDoc);
      when(() => groupDoc.collection(GroupCollections.joinRequests))
          .thenReturn(joinRequests);
      when(() => joinRequests.doc('u1')).thenReturn(joinDoc);
      when(() => joinDoc.set(any())).thenThrow(err);

      final crash = MockCrashlytics();
      ErrorLogger.crashlytics = crash;
      when(() => crash.recordError(any(), any(),
          reason: any(named: 'reason'),
          information: any(named: 'information'),
          printDetails: any(named: 'printDetails'),
          fatal: any(named: 'fatal'))).thenAnswer((_) async {});

      final svc = GroupService(firestore: mockFs);

      await expectLater(svc.joinGroup(groupId: 'g1', uid: 'u1', name: 'Name'),
          throwsA(same(err)));

      verify(() => joinRequests.doc('u1')).called(1);
      verify(() => joinDoc.set(any())).called(1);
      verify(() => crash.recordError(err, any(),
          reason: null,
          information: any(named: 'information'),
          printDetails: any(named: 'printDetails'),
          fatal: false)).called(1);
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
      when(() => memberDoc.delete())
          .thenAnswer((_) => Future<void>.error(Exception('fail')));

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
