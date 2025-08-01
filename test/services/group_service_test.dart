import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/models/group_schedule.dart';

void main() {
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
    });

    test('fetchTodaysChapters returns schedule for today', () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      final now = DateTime.now();
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
  });
}
