// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bible_read/models/group.dart';
import 'package:bible_read/models/group_member_progress.dart';
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

    // Mock Crashlytics channel
    const channel = MethodChannel('plugins.flutter.io/firebase_crashlytics');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return null;
    });

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

      expect(id, isNotEmpty);

      final doc =
          await firestore.collection(GroupCollections.groups).doc(id).get();
      expect(doc.exists, isTrue);
      expect(doc.data(), {
        'name': 'Test',
        'ownerUid': 'u1',
        'memberCount': 1,
        'isPublic': false,
      });

      final member = await firestore
          .collection(GroupCollections.groups)
          .doc(id)
          .collection(GroupCollections.members)
          .doc('u1')
          .get();
      expect(member.exists, isTrue);

      final data = member.data()!;
      expect(data['uid'], 'u1');
      expect(data['role'], 'owner');
      expect(data['joinedAt'], isA<Timestamp>());
      // Verify timestamp is recent (within 1 minute)
      final joinedAt = (data['joinedAt'] as Timestamp).toDate();
      expect(joinedAt.difference(DateTime.now()).inMinutes.abs(), lessThan(1));
      // Ensure no unexpected fields
      expect(data.keys.length, 3);
    });

    test('createGroup throws ArgumentError when name is empty', () async {
      await expectLater(
        service.createGroup(ownerUid: 'u1', name: ''),
        throwsArgumentError,
      );
      await expectLater(
        service.createGroup(ownerUid: 'u1', name: '   '),
        throwsArgumentError,
      );
    });

    test('createGroup uses correct name fallback', () async {
      // 1. User Name
      await firestore.collection('users').doc('u1').set({
        'name': 'Real Name',
        'displayName': 'Display Name',
        'email': 'email@test.com',
      });
      var id = await service.createGroup(ownerUid: 'u1', name: 'G1');
      var member = await firestore
          .collection(GroupCollections.groups)
          .doc(id)
          .collection(GroupCollections.members)
          .doc('u1')
          .get();
      expect(member.data()?['name'], 'Real Name');

      // 2. Display Name
      await firestore.collection('users').doc('u2').set({
        'displayName': 'Display Name',
        'email': 'email@test.com',
      });
      id = await service.createGroup(ownerUid: 'u2', name: 'G2');
      member = await firestore
          .collection(GroupCollections.groups)
          .doc(id)
          .collection(GroupCollections.members)
          .doc('u2')
          .get();
      expect(member.data()?['name'], 'Display Name');

      // 3. Email Username
      await firestore.collection('users').doc('u3').set({
        'email': 'user@test.com',
      });
      id = await service.createGroup(ownerUid: 'u3', name: 'G3');
      member = await firestore
          .collection(GroupCollections.groups)
          .doc(id)
          .collection(GroupCollections.members)
          .doc('u3')
          .get();
      expect(member.data()?['name'], 'user');
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

      // Verify owner gets the notification with correct fields
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
      expect(data['groupId'], 'g1');
      expect(data['message'], 'User requested to join your group');
      expect(data['read'], false);
      expect(data['timestamp'], isA<Timestamp>());

      // Verify unrelated users do NOT get notified
      final unrelatedSnap = await firestore
          .collection(NotificationCollections.users)
          .doc('u3')
          .collection(NotificationCollections.notifications)
          .get();
      expect(unrelatedSnap.docs, isEmpty);
    });

    test('joinGroup throws StateError when group does not exist', () async {
      await expectLater(
        service.joinGroup(groupId: 'missing', uid: 'u1', name: 'User'),
        throwsStateError,
      );

      final requests = await firestore
          .collection(GroupCollections.groups)
          .doc('missing')
          .collection(GroupCollections.joinRequests)
          .get();
      expect(requests.docs, isEmpty);
    });

    test('approveJoinRequest moves member and removes request', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1', 'memberCount': 1});
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
      final groupDoc = await groupRef.get();
      expect(groupDoc.data()?['memberCount'], 2);
    });

    test('approveJoinRequest seeds memberCount when missing', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      await groupRef.collection(GroupCollections.members).doc('u1').set({
        'uid': 'u1',
        'role': 'owner',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
      });
      await groupRef.collection(GroupCollections.joinRequests).doc('u2').set({
        'uid': 'u2',
        'name': 'User',
        'requestedAt': Timestamp.fromDate(DateTime.utc(2024, 2, 1)),
      });

      await service.approveJoinRequest(groupId: 'g1', uid: 'u2');

      final groupDoc = await groupRef.get();
      expect(groupDoc.data()?['memberCount'], 2);
    });

    test('denyJoinRequest removes request without adding member', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1', 'memberCount': 2});
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
      await groupRef.set({'name': 'G', 'ownerUid': 'u1', 'memberCount': 2});
      await groupRef.collection(GroupCollections.members).doc('u2').set({
        'uid': 'u2',
        'role': 'member',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024)),
      });

      await service.leaveGroup(groupId: 'g1', uid: 'u2');

      final member =
          await groupRef.collection(GroupCollections.members).doc('u2').get();
      expect(member.exists, isFalse);
      final groupDoc = await groupRef.get();
      expect(groupDoc.data()?['memberCount'], 1);
    });

    test('leaveGroup seeds memberCount when missing', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      await groupRef.collection(GroupCollections.members).doc('u1').set({
        'uid': 'u1',
        'role': 'owner',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
      });
      await groupRef.collection(GroupCollections.members).doc('u2').set({
        'uid': 'u2',
        'role': 'member',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 2)),
      });

      await service.leaveGroup(groupId: 'g1', uid: 'u2');

      final groupDoc = await groupRef.get();
      expect(groupDoc.data()?['memberCount'], 1);
      final remaining =
          await groupRef.collection(GroupCollections.members).doc('u2').get();
      expect(remaining.exists, isFalse);
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

      // Use emits to verify immediate state, removing brittle firstWhere
      await expectLater(
        service.allGroups(),
        emits(
          isA<List<Group>>().having((l) => l.length, 'length', 3).having(
              (l) => l.map((g) => g.id).toSet(), 'ids', {'g1', 'g2', 'g3'}),
        ),
      );
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

      await expectLater(
        service.groupsForUser('u1'),
        emitsThrough(
          isA<List<Group>>()
              .having((l) => l.length, 'length', 2)
              .having((l) => l.map((g) => g.id).toSet(), 'ids', {'g1', 'g2'}),
        ),
      );
    });

    test('groupsForUser includes owned groups without membership doc',
        () async {
      final owned = firestore.collection(GroupCollections.groups).doc('g1');
      await owned.set({'name': 'G', 'ownerUid': 'u1'});

      await expectLater(
        service.groupsForUser('u1'),
        emitsThrough(
          isA<List<Group>>()
              .having((l) => l.length, 'length', 1)
              .having((l) => l.first.id, 'id', 'g1'),
        ),
      );
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

      await expectLater(
        service.groupsForUser('u1'),
        emitsThrough(
          isA<List<Group>>()
              .having((l) => l.length, 'length', 1)
              .having((l) => l.first.id, 'id', 'g1'),
        ),
      );
    });

    test('groupsForUser deduplicates owned membership groups', () async {
      final owned = firestore.collection(GroupCollections.groups).doc('g1');
      await owned.set({'name': 'G', 'ownerUid': 'u1'});
      await owned.collection(GroupCollections.members).doc('m1').set({
        'uid': 'u1',
        'role': 'owner',
        'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
      });

      await expectLater(
        service.groupsForUser('u1'),
        emitsThrough(
          isA<List<Group>>()
              .having((l) => l.length, 'length', 1)
              .having((l) => l.first.id, 'id', 'g1'),
        ),
      );
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

      await expectLater(
        service.memberNames('g1'),
        emitsThrough(
          isA<List<String>>().having(
            (l) => l.toSet(),
            'names',
            {'Alice', 'Bob'},
          ),
        ),
      );
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

      await expectLater(
        service.memberNames('g1'),
        emitsThrough(
          isA<List<String>>().having(
            (l) => l.toSet(),
            'names',
            expected,
          ),
        ),
      );
    });

    test('memberNames falls back to displayName or email when name is missing',
        () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});

      // Member 1: Has name in users (Normal case)
      await firestore.collection('users').doc('u1').set({'name': 'Alice'});
      await groupRef.collection(GroupCollections.members).doc('m1').set({
        'uid': 'u1',
        'role': 'owner',
      });

      // Member 2: Has displayName in users (Fallback case 1)
      await firestore.collection('users').doc('u2').set({'displayName': 'Bob'});
      await groupRef.collection(GroupCollections.members).doc('m2').set({
        'uid': 'u2',
        'role': 'member',
      });

      // Member 3: Has email in users (Fallback case 2)
      await firestore
          .collection('users')
          .doc('u3')
          .set({'email': 'charlie@test.com'});
      await groupRef.collection(GroupCollections.members).doc('m3').set({
        'uid': 'u3',
        'role': 'member',
      });

      await expectLater(
        service.memberNames('g1'),
        emitsThrough(
          isA<List<String>>().having(
            (l) => l.toSet(),
            'names',
            {'Alice', 'Bob', 'charlie'},
          ),
        ),
      );
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

      await expectLater(
        service.schedule('g1'),
        emitsThrough(
          isA<List<GroupSchedule>>()
              .having((l) => l.length, 'length', 1)
              .having((l) => l.first.chapters, 'chapters', ['Gen 1']),
        ),
      );
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

    test('memberDailyCompletion streams progress for group members', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});

      // Members
      await groupRef.collection(GroupCollections.members).doc('u1').set({
        'uid': 'u1',
        'name': 'Alice',
        'role': 'owner',
      });
      await groupRef.collection(GroupCollections.members).doc('u2').set({
        'uid': 'u2',
        'name': 'Bob',
        'role': 'member',
      });

      // Schedule for today
      final today = DateTime.now();
      final dateId =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      await groupRef.collection(GroupCollections.schedule).doc(dateId).set({
        'date': Timestamp.fromDate(
            DateTime.utc(today.year, today.month, today.day)),
        'chapters': ['Gen 1', 'Gen 2'] // 2 chapters
      });

      // Progress: u1 read 1 chapter (50%)
      await groupRef
          .collection('progress')
          .doc(dateId)
          .collection('entries')
          .doc('u1')
          .set({'count': 1}); // Optimized logic relies on 'count'

      await groupRef
          .collection('progress')
          .doc(dateId)
          .collection('entries')
          .doc('u1')
          .collection('items')
          .doc('Gen 1')
          .set({});

      // Progress: u2 read 2 chapters (100%)
      await groupRef
          .collection('progress')
          .doc(dateId)
          .collection('entries')
          .doc('u2')
          .set({'count': 2}); // Optimized logic relies on 'count'

      await groupRef
          .collection('progress')
          .doc(dateId)
          .collection('entries')
          .doc('u2')
          .collection('items')
          .doc('Gen 1')
          .set({});
      await groupRef
          .collection('progress')
          .doc(dateId)
          .collection('entries')
          .doc('u2')
          .collection('items')
          .doc('Gen 2')
          .set({});

      await expectLater(
        service.memberDailyCompletion('g1', date: today),
        emitsThrough(
          isA<List<GroupMemberProgressData>>()
              .having((l) => l.length, 'length', 2)
              .having(
                (l) => l.firstWhere((m) => m.uid == 'u1'),
                'u1',
                isA<GroupMemberProgressData>()
                    .having((m) => m.completion, 'completion', 0.5)
                    .having((m) => m.name, 'name', 'Alice'),
              )
              .having(
                (l) => l.firstWhere((m) => m.uid == 'u2'),
                'u2',
                isA<GroupMemberProgressData>()
                    .having((m) => m.completion, 'completion', 1.0)
                    .having((m) => m.name, 'name', 'Bob'),
              ),
        ),
      );
    });

    test('memberDailyCompletion returns 0% when no progress exists', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      await groupRef.collection(GroupCollections.members).doc('u1').set({
        'uid': 'u1',
        'name': 'Alice',
      });

      final today = DateTime.now();
      final dateId =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      await groupRef.collection(GroupCollections.schedule).doc(dateId).set({
        'date': Timestamp.fromDate(
            DateTime.utc(today.year, today.month, today.day)),
        'chapters': ['Gen 1']
      });

      await expectLater(
        service.memberDailyCompletion('g1', date: today),
        emitsThrough(
          isA<List<GroupMemberProgressData>>()
              .having((l) => l.length, 'length', 1)
              .having((l) => l.first.completion, 'completion', 0.0),
        ),
      );
    });

    test('deleteGroup removes group and subcollections', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});

      // Populate subcollections
      await groupRef.collection(GroupCollections.members).doc('u1').set({});
      await groupRef.collection(GroupCollections.schedule).doc('d1').set({});
      await groupRef
          .collection(GroupCollections.joinRequests)
          .doc('u2')
          .set({});

      // Execute delete
      await service.deleteGroup(groupId: 'g1', ownerUid: 'u1');

      expect((await groupRef.get()).exists, isFalse);
      expect((await groupRef.collection(GroupCollections.members).get()).docs,
          isEmpty);
      expect((await groupRef.collection(GroupCollections.schedule).get()).docs,
          isEmpty);
      expect(
          (await groupRef.collection(GroupCollections.joinRequests).get()).docs,
          isEmpty);
    });

    test('deleteGroup throws if caller is not owner', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});

      await expectLater(
        service.deleteGroup(groupId: 'g1', ownerUid: 'u2'),
        throwsStateError,
      );

      expect((await groupRef.get()).exists, isTrue);
    });

    test('memberOverallCompletion streams total progress for group members',
        () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});

      // Members
      await groupRef.collection(GroupCollections.members).doc('u1').set({
        'uid': 'u1',
        'name': 'Alice',
        'role': 'owner',
      });
      await groupRef.collection(GroupCollections.members).doc('u2').set({
        'uid': 'u2',
        'name': 'Bob',
        'role': 'member',
      });

      // Schedule: Total 4 chapters
      await groupRef
          .collection(GroupCollections.schedule)
          .doc('2024-01-01')
          .set({
        'date': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
        'chapters': ['Gen 1', 'Gen 2'],
      });
      await groupRef
          .collection(GroupCollections.schedule)
          .doc('2024-01-02')
          .set({
        'date': Timestamp.fromDate(DateTime.utc(2024, 1, 2)),
        'chapters': ['Gen 3', 'Gen 4'],
      });

      // Progress Summary
      // u1: Completed 3 chapters (75%)
      await groupRef
          .collection('progressSummary')
          .doc('data')
          .collection('entries')
          .doc('u1')
          .set({'completed': 3});

      // u2: Completed 0 chapters (0%) - No entry or entry with 0

      await expectLater(
        service.memberOverallCompletion('g1'),
        emitsThrough(
          isA<List<GroupMemberProgressData>>()
              .having((l) => l.length, 'length', 2)
              .having(
                (l) => l.firstWhere((m) => m.uid == 'u1'),
                'u1',
                isA<GroupMemberProgressData>()
                    .having((m) => m.completion, 'completion', 0.75)
                    .having((m) => m.name, 'name', 'Alice'),
              )
              .having(
                (l) => l.firstWhere((m) => m.uid == 'u2'),
                'u2',
                isA<GroupMemberProgressData>()
                    .having((m) => m.completion, 'completion', 0.0)
                    .having((m) => m.name, 'name', 'Bob'),
              ),
        ),
      );
    });

    group('Recalc & Fix Progress', () {
      test('recalcProgressForUserInGroup sums counts and updates summary',
          () async {
        final groupRef =
            firestore.collection(GroupCollections.groups).doc('g1');
        await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
        await groupRef.collection(GroupCollections.members).doc('u1').set({
          'uid': 'u1',
          'role': 'owner',
        });

        // Date 1: 2 items
        await groupRef.collection('progress').doc('d1').set({});
        await groupRef
            .collection('progress')
            .doc('d1')
            .collection('entries')
            .doc('u1')
            .set({'count': 2, 'uid': 'u1', 'groupId': 'g1'});

        // Date 2: 3 items
        await groupRef.collection('progress').doc('d2').set({});
        await groupRef
            .collection('progress')
            .doc('d2')
            .collection('entries')
            .doc('u1')
            .set({'count': 3, 'uid': 'u1', 'groupId': 'g1'});

        // Pre-existing summary (wrong value to verify update)
        await groupRef
            .collection('progressSummary')
            .doc('data')
            .collection('entries')
            .doc('u1')
            .set({'completed': 0});

        await service.recalcProgressForUserInGroup(groupId: 'g1', uid: 'u1');

        final summary = await groupRef
            .collection('progressSummary')
            .doc('data')
            .collection('entries')
            .doc('u1')
            .get();
        expect(summary.data()?['completed'], 5);
      });

      test('recalcProgressForUserInGroup backfills missing count', () async {
        final groupRef =
            firestore.collection(GroupCollections.groups).doc('g1');
        await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
        await groupRef.collection(GroupCollections.members).doc('u1').set({
          'uid': 'u1',
          'role': 'owner',
        });

        // Date 1: Entry exists but no count. Has 2 items.
        await groupRef.collection('progress').doc('d1').set({});
        final entryRef = groupRef
            .collection('progress')
            .doc('d1')
            .collection('entries')
            .doc('u1');
        await entryRef.set({
          'uid': 'u1',
          'groupId': 'g1'
        }); // Entry with uid/groupId but no count
        await entryRef.collection('items').doc('i1').set({});
        await entryRef.collection('items').doc('i2').set({});

        await service.recalcProgressForUserInGroup(groupId: 'g1', uid: 'u1');

        final entry = await entryRef.get();
        expect(entry.data()?['count'], 2);

        final summary = await groupRef
            .collection('progressSummary')
            .doc('data')
            .collection('entries')
            .doc('u1')
            .get();
        expect(summary.data()?['completed'], 2);
      });

      test('recalcProgressForUserInGroup does nothing if user not member/owner',
          () async {
        final groupRef =
            firestore.collection(GroupCollections.groups).doc('g1');
        await groupRef.set({'name': 'G', 'ownerUid': 'owner'});
        // u1 is not a member

        await groupRef.collection('progress').doc('d1').set({});
        await groupRef
            .collection('progress')
            .doc('d1')
            .collection('entries')
            .doc('u1')
            .set({'count': 5});

        await service.recalcProgressForUserInGroup(groupId: 'g1', uid: 'u1');

        final summary = await groupRef
            .collection('progressSummary')
            .doc('data')
            .collection('entries')
            .doc('u1')
            .get();
        expect(summary.exists, isFalse);
      });

      test('fixMemberProgressSummariesForUser updates all groups for user',
          () async {
        // Group 1
        final g1 = firestore.collection(GroupCollections.groups).doc('g1');
        await g1.set({'name': 'G1', 'ownerUid': 'u1'});
        await g1
            .collection(GroupCollections.members)
            .doc('u1')
            .set({'uid': 'u1', 'role': 'owner'});
        await g1.collection('progress').doc('d1').set({});
        await g1
            .collection('progress')
            .doc('d1')
            .collection('entries')
            .doc('u1')
            .set({'count': 2, 'uid': 'u1', 'groupId': 'g1'});

        // Group 2
        final g2 = firestore.collection(GroupCollections.groups).doc('g2');
        await g2.set({'name': 'G2', 'ownerUid': 'u2'});
        await g2
            .collection(GroupCollections.members)
            .doc('u1')
            .set({'uid': 'u1', 'role': 'member'});
        await g2.collection('progress').doc('d1').set({});
        await g2
            .collection('progress')
            .doc('d1')
            .collection('entries')
            .doc('u1')
            .set({'count': 3, 'uid': 'u1', 'groupId': 'g2'});

        await service.fixMemberProgressSummariesForUser('u1');

        final s1 = await g1
            .collection('progressSummary')
            .doc('data')
            .collection('entries')
            .doc('u1')
            .get();
        expect(s1.data()?['completed'], 2);

        final s2 = await g2
            .collection('progressSummary')
            .doc('data')
            .collection('entries')
            .doc('u1')
            .get();
        expect(s2.data()?['completed'], 3);
      });
    });

    group('Error Handling (requires Mockito)', () {
      // NOTE: These tests use MockFirebaseFirestore because FakeFirebaseFirestore
      // does not support easy injection of errors into streams or write operations.
      // While brittle, these are necessary to ensure the service handles Firestore
      // outages gracefully.

      test('groupsForUser logs and returns empty list on stream error',
          () async {
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
          return Stream<QuerySnapshot<Map<String, dynamic>>>.error(err);
        });

        when(() => mockFs.collection(GroupCollections.groups))
            .thenReturn(groups);
        when(() => groups.where('ownerUid', isEqualTo: 'u1'))
            .thenReturn(ownerQuery);
        when(() => ownerQuery.snapshots())
            .thenAnswer((_) => Stream.value(ownerSnap));
        when(() => ownerSnap.docs).thenReturn([]);

        final joinQuery = MockQuery<Map<String, dynamic>>();
        final joinSnap = MockQuerySnapshot<Map<String, dynamic>>();

        when(() => mockFs.collectionGroup(GroupCollections.joinRequests))
            .thenReturn(joinQuery);
        when(() => joinQuery.where('uid', isEqualTo: 'u1'))
            .thenReturn(joinQuery);
        when(() => joinQuery.snapshots())
            .thenAnswer((_) => Stream.value(joinSnap));
        when(() => joinSnap.docs).thenReturn([]);

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

        when(() => mockFs.collection(GroupCollections.groups))
            .thenReturn(groups);
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

        await runZonedGuarded(() async {
          await expectLater(svc.allGroups(), emits(isEmpty));
        }, (e, st) {});

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

        when(() => mockFs.collection(GroupCollections.groups))
            .thenReturn(groups);
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

        await runZonedGuarded(() async {
          await expectLater(svc.memberNames('g1'), emitsError(same(err)));
        }, (e, st) {});
      });

      test('schedule surfaces stream errors', () async {
        final mockFs = MockFirebaseFirestore();
        final groups = MockCollectionReference<Map<String, dynamic>>();
        final groupDoc = MockDocumentReference<Map<String, dynamic>>();
        final schedule = MockCollectionReference<Map<String, dynamic>>();
        final query = MockQuery<Map<String, dynamic>>();
        final err = Exception('fail');

        when(() => mockFs.collection(GroupCollections.groups))
            .thenReturn(groups);
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

        await runZonedGuarded(() async {
          await expectLater(svc.schedule('g1'), emitsError(same(err)));
        }, (e, st) {});
      });

      test('joinGroup rethrows and logs on error', () async {
        final mockFs = MockFirebaseFirestore();
        final groups = MockCollectionReference<Map<String, dynamic>>();
        final groupDoc = MockDocumentReference<Map<String, dynamic>>();
        final joinRequests = MockCollectionReference<Map<String, dynamic>>();
        final joinDoc = MockDocumentReference<Map<String, dynamic>>();
        final err = Exception('fail');

        final groupSnap = MockDocumentSnapshot<Map<String, dynamic>>();
        when(() => groupSnap.exists).thenReturn(true);
        when(() => groupSnap.data()).thenReturn({'ownerUid': 'owner'});

        when(() => mockFs.collection(GroupCollections.groups))
            .thenReturn(groups);
        when(() => groups.doc('g1')).thenReturn(groupDoc);
        when(() => groupDoc.get()).thenAnswer((_) async => groupSnap);
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

      test('leaveGroup rethrows and logs on error', () async {
        final mockFs = MockFirebaseFirestore();
        final groups = MockCollectionReference<Map<String, dynamic>>();
        final groupDoc = MockDocumentReference<Map<String, dynamic>>();
        final members = MockCollectionReference<Map<String, dynamic>>();
        final memberDoc = MockDocumentReference<Map<String, dynamic>>();
        final memberSnap = MockDocumentSnapshot<Map<String, dynamic>>();
        final groupSnap = MockDocumentSnapshot<Map<String, dynamic>>();
        final batch = MockWriteBatch();

        when(() => mockFs.collection(GroupCollections.groups))
            .thenReturn(groups);
        when(() => groups.doc('g1')).thenReturn(groupDoc);
        when(() => groupDoc.collection(GroupCollections.members))
            .thenReturn(members);
        when(() => members.doc('u1')).thenReturn(memberDoc);
        when(() => memberDoc.get()).thenAnswer((_) async => memberSnap);
        when(() => memberSnap.exists).thenReturn(true);
        when(() => groupDoc.get()).thenAnswer((_) async => groupSnap);
        when(() => groupSnap.exists).thenReturn(true);
        when(() => groupSnap.data()).thenReturn({'memberCount': 1});
        when(() => mockFs.batch()).thenReturn(batch);
        when(() => batch.commit())
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
  });
}
