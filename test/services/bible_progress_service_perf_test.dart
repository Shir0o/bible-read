import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/services/bible_progress_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BibleProgressService Performance', () {
    const userId = 'user1';
    late FakeFirebaseFirestore firestore;
    late BibleProgressService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = BibleProgressService(firestore: firestore);
    });

    String dateId0(DateTime date) {
      final y = date.year.toString().padLeft(4, '0');
      final m = date.month.toString().padLeft(2, '0');
      final d = date.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    test('measure completedChaptersByBook with 2 groups and 100 days history',
        () async {
      // Setup 2 groups
      for (var g = 1; g <= 2; g++) {
        final groupId = 'g$g';
        final groupRef = firestore.collection('groups').doc(groupId);
        await groupRef.set({
          'name': 'Group $groupId',
          'ownerUid': userId,
        });
        await groupRef.collection('members').doc(userId).set({'uid': userId});

        // Seed 100 days of schedule
        // Batch writes for speed in seeding
        var batch = firestore.batch();
        var opCount = 0;
        final startDate = DateTime(2024, 1, 1);

        for (var i = 0; i < 100; i++) {
          final date = startDate.add(Duration(days: i));
          final dateId = dateId0(date);

          // Schedule
          final scheduleRef = groupRef.collection('schedule').doc(dateId);
          batch.set(scheduleRef, {
            'date': Timestamp.fromDate(
                DateTime.utc(date.year, date.month, date.day)),
            'chapters': ['Gen 1', 'Gen 2'],
          });
          opCount++;

          // Entry (every other day)
          if (i % 2 == 0) {
            final entryRef = groupRef
                .collection('progress')
                .doc(dateId)
                .collection('entries')
                .doc(userId);
            batch.set(entryRef, {
              'uid': userId,
              'groupId': groupId,
              'dateId': dateId,
              'count': 1, // Partial
              'done': false,
            });
            opCount++;

            // Items
            final itemRef = entryRef.collection('items').doc('0');
            batch.set(itemRef, {'done': true});
            opCount++;
          }

          if (opCount > 400) {
            await batch.commit();
            batch = firestore.batch();
            opCount = 0;
          }
        }
        await batch.commit();
      }

      final stopwatch = Stopwatch()..start();

      final result = await service.completedChaptersByBook(userId);

      stopwatch.stop();

      // Verification (sanity check)
      // 2 groups * 50 entries each = 100 entries.
      // Each entry has 1 chapter completed ('Gen 1').
      // So 'Gen' should have {1}.
      // Wait, 'Gen 1' is chapter 1.
      expect(result['Genesis'], equals({1}));
    });
  });
}
