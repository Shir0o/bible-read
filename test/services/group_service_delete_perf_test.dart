// ignore_for_file: avoid_print

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

  group('GroupService Delete Performance', () {
    late FakeFirebaseFirestore firestore;
    late GroupService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = GroupService(firestore: firestore);
    });

    test('deleteGroup handles large group deletion', () async {
      // Setup
      final groupRef = firestore.collection('groups').doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'owner'});

      print('Seeding data...');

      // 1. Members: 50 members
      for (var i = 0; i < 50; i++) {
        await groupRef.collection('members').doc('u$i').set({
          'uid': 'u$i',
          'role': i == 0 ? 'owner' : 'member',
        });
      }

      // 2. Schedule: 365 days
      final scheduleBatch = firestore.batch();
      for (var i = 0; i < 365; i++) {
        final dateId =
            '2024-${(i ~/ 30 + 1).toString().padLeft(2, '0')}-${(i % 30 + 1).toString().padLeft(2, '0')}';
        scheduleBatch.set(groupRef.collection('schedule').doc(dateId), {
          'date': Timestamp.now(),
          'chapters': ['Gen 1']
        });
      }
      await scheduleBatch.commit();

      // 3. Progress: 100 days, 10 members each
      // Creating nested structure: progress/{dateId}/entries/{uid}
      for (var d = 0; d < 100; d++) {
        final dateId =
            '2024-${(d ~/ 30 + 1).toString().padLeft(2, '0')}-${(d % 30 + 1).toString().padLeft(2, '0')}';
        final dateRef = groupRef.collection('progress').doc(dateId);
        await dateRef.set({}); // Create date doc

        for (var m = 0; m < 10; m++) {
          await dateRef.collection('entries').doc('u$m').set({'count': 1});
        }
      }

      print('Seeding complete.');

      // Benchmark
      final stopwatch = Stopwatch()..start();
      await service.deleteGroup(groupId: 'g1', ownerUid: 'owner');
      stopwatch.stop();

      print('deleteGroup took: ${stopwatch.elapsedMilliseconds}ms');

      // Verify deletion
      final groupSnap = await groupRef.get();
      expect(groupSnap.exists, false);

      final membersSnap = await groupRef.collection('members').get();
      expect(membersSnap.docs.isEmpty, true);
    });
  });
}
