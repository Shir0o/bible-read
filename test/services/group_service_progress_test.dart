// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bible_read/services/group_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(SetOptions(merge: true));
    await Firebase.initializeApp();
  });

  group('GroupService Progress', () {
    late FakeFirebaseFirestore firestore;
    late GroupService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = GroupService(firestore: firestore);
    });

    String dateId(DateTime d) {
      final y = d.year.toString().padLeft(4, '0');
      final m = d.month.toString().padLeft(2, '0');
      final day = d.day.toString().padLeft(2, '0');
      return '$y-$m-$day';
    }

    test('memberDailyCompletion calculates correct percentages', () async {
      final groupId = 'g1';
      final now = DateTime.now();
      final date = DateTime.utc(now.year, now.month, now.day);
      final did = dateId(date);

      // 1. Setup Group & Members
      await firestore.collection('groups').doc(groupId).set({
        'name': 'G1',
        'ownerUid': 'u1',
      });
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc('u1')
          .set({'uid': 'u1', 'name': 'User1'});
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc('u2')
          .set({'uid': 'u2', 'name': 'User2'});

      // 2. Setup Schedule (2 chapters)
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('schedule')
          .doc(did)
          .set({
            'date': Timestamp.fromDate(date),
            'chapters': ['Gen 1', 'Gen 2'],
          });

      // 3. Setup Progress
      // u1: 1 item checked (50%)
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('progress')
          .doc(did)
          .collection('entries')
          .doc('u1')
          .set({'count': 1});

      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('progress')
          .doc(did)
          .collection('entries')
          .doc('u1')
          .collection('items')
          .doc('i1')
          .set({'checked': true});

      // u2: 2 items checked (100%)
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('progress')
          .doc(did)
          .collection('entries')
          .doc('u2')
          .set({'count': 2});

      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('progress')
          .doc(did)
          .collection('entries')
          .doc('u2')
          .collection('items')
          .doc('i1')
          .set({'checked': true});
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('progress')
          .doc(did)
          .collection('entries')
          .doc('u2')
          .collection('items')
          .doc('i2')
          .set({'checked': true});

      // 4. Test
      final stream = service.memberDailyCompletion(groupId, date: date);
      final result = await stream.firstWhere((list) => list.length == 2);

      final u1 = result.firstWhere((m) => m.uid == 'u1');
      final u2 = result.firstWhere((m) => m.uid == 'u2');

      expect(u1.completion, 0.5);
      expect(u2.completion, 1.0);
    });

    test('memberDailyCompletion handles missing data gracefuly', () async {
      final groupId = 'g1';
      final now = DateTime.now();
      final date = DateTime.utc(now.year, now.month, now.day);

      // Setup Group with member but NO Schedule and NO Progress
      await firestore.collection('groups').doc(groupId).set({
        'name': 'G1',
        'ownerUid': 'u1',
      });
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc('u1')
          .set({'uid': 'u1', 'name': 'User1'});

      // Even with no schedule, it should return 0.0, not crash
      final stream = service.memberDailyCompletion(groupId, date: date);
      final result = await stream.first;

      expect(result.length, 1);
      expect(result.first.completion, 0.0);
    });

    test(
      'memberDailyCompletion fetches names from users collection if missing in member doc',
      () async {
        final groupId = 'g1';
        final now = DateTime.now();
        final date = DateTime.utc(now.year, now.month, now.day);

        await firestore.collection('groups').doc(groupId).set({
          'name': 'G1',
          'ownerUid': 'u1',
        });
        // Member doc without name
        await firestore
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .doc('u1')
            .set({'uid': 'u1'}); // Name missing here

        // User doc has name
        await firestore.collection('users').doc('u1').set({
          'name': 'Real Name',
        });

        final stream = service.memberDailyCompletion(groupId, date: date);
        final result = await stream.firstWhere(
          (l) => l.isNotEmpty && l.first.name == 'Real Name',
        );

        expect(result.first.name, 'Real Name');
      },
    );
  });
}
