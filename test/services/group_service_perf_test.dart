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

  group('GroupService Performance', () {
    late FakeFirebaseFirestore firestore;
    late GroupService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = GroupService(firestore: firestore);
    });

    test('recalcProgressForUserInGroup handles 365 days of progress', () async {
      // Setup
      final groupRef = firestore.collection('groups').doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
      await groupRef.collection('members').doc('u1').set({
        'uid': 'u1',
        'role': 'owner',
      });

      // Populate 365 days of progress
      print('Seeding 365 days of data...');
      final batchSize = 500;
      var batch = firestore.batch();
      var opCount = 0;

      for (var i = 0; i < 365; i++) {
        final dateId =
            '2024-${(i ~/ 30 + 1).toString().padLeft(2, '0')}-${(i % 30 + 1).toString().padLeft(2, '0')}';
        final dateRef = groupRef.collection('progress').doc(dateId);
        batch.set(dateRef, <String, dynamic>{});

        final entryRef = dateRef.collection('entries').doc('u1');
        batch.set(entryRef, <String, dynamic>{
          'count': 1
        }); // Assume count exists to focus on read speed

        opCount += 2;
        if (opCount >= batchSize) {
          await batch.commit();
          batch = firestore.batch();
          opCount = 0;
        }
      }
      await batch.commit();
      print('Seeding complete.');

      // Benchmark
      final stopwatch = Stopwatch()..start();
      await service.recalcProgressForUserInGroup(groupId: 'g1', uid: 'u1');
      stopwatch.stop();

      print(
          'recalcProgressForUserInGroup took: ${stopwatch.elapsedMilliseconds}ms');

      // Verify result
      final summary = await groupRef
          .collection('progressSummary')
          .doc('data')
          .collection('entries')
          .doc('u1')
          .get();
      expect(summary.data()?['completed'], 365);
    });
  });
}
