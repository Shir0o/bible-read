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

  group('GroupService Leave Performance', () {
    late FakeFirebaseFirestore firestore;
    late GroupService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = GroupService(firestore: firestore);
    });

    test('leaveGroup handles large history cleanup', () async {
      // Setup
      final groupRef = firestore.collection('groups').doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'owner', 'memberCount': 2});

      print('Seeding data...');

      // 1. Members
      await groupRef.collection('members').doc('owner').set({
        'uid': 'owner',
        'role': 'owner',
      });
      await groupRef.collection('members').doc('leaver').set({
        'uid': 'leaver',
        'role': 'member',
      });

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

      // 3. Progress: 100 days for 'leaver'
      // Creating nested structure: progress/{dateId}/entries/leaver
      for (var d = 0; d < 100; d++) {
        final dateId =
            '2024-${(d ~/ 30 + 1).toString().padLeft(2, '0')}-${(d % 30 + 1).toString().padLeft(2, '0')}';
        final dateRef = groupRef.collection('progress').doc(dateId);
        await dateRef.set({}); // Create date doc

        // Create entry for leaver
        final entryRef = dateRef.collection('entries').doc('leaver');
        await entryRef.set({'count': 3});

        // Add items for the entry
        for (var i = 0; i < 3; i++) {
            await entryRef.collection('items').doc('item$i').set({});
        }
      }

      print('Seeding complete.');

      // Benchmark
      final stopwatch = Stopwatch()..start();
      await service.leaveGroup(groupId: 'g1', uid: 'leaver');
      stopwatch.stop();

      print('leaveGroup took: ${stopwatch.elapsedMilliseconds}ms');

      // Verify deletion
      final memberSnap = await groupRef.collection('members').doc('leaver').get();
      expect(memberSnap.exists, false);

      // Verify progress cleanup
      // Check a few dates to ensure 'leaver' entries are gone
      final progressDates = await groupRef.collection('progress').get();
      for (final dateDoc in progressDates.docs) {
          final entryRef = dateDoc.reference.collection('entries').doc('leaver');
          final entrySnap = await entryRef.get();
          expect(entrySnap.exists, false, reason: 'Entry for leaver should be deleted in date ${dateDoc.id}');
      }
    });
  });
}
