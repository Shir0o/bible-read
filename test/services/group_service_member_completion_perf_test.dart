import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/services/group_service.dart';

void main() {
  test('memberDailyCompletion benchmark', () async {
    final firestore = FakeFirebaseFirestore();
    final service = GroupService(firestore: firestore);

    const groupId = 'g1';
    const memberCount = 100;
    const chaptersPerDay = 5;

    // Create group
    await firestore.collection('groups').doc(groupId).set({
      'name': 'Benchmark Group',
      'ownerUid': 'user_0',
      'memberCount': memberCount,
    });

    // Create schedule for today
    final today = DateTime.now();
    // Replicate _dateId logic
    final y = today.year.toString().padLeft(4, '0');
    final m = today.month.toString().padLeft(2, '0');
    final d = today.day.toString().padLeft(2, '0');
    final dateId = '$y-$m-$d';

    await firestore
        .collection('groups')
        .doc(groupId)
        .collection('schedule')
        .doc(dateId)
        .set({
          'date': today,
          'chapters': List.generate(chaptersPerDay, (i) => 'Gen ${i + 1}'),
        });

    // Create members and progress
    var batch = firestore.batch();
    var opCount = 0;
    for (var i = 0; i < memberCount; i++) {
      final uid = 'user_$i';
      // Member
      batch.set(
        firestore
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .doc(uid),
        {'uid': uid, 'name': 'User $i', 'role': 'member'},
      );
      opCount++;

      // Progress Entry
      final entryRef = firestore
          .collection('groups')
          .doc(groupId)
          .collection('progress')
          .doc(dateId)
          .collection('entries')
          .doc(uid);

      batch.set(entryRef, {
        'count': chaptersPerDay, // Fully completed
        'completed': chaptersPerDay, // Just in case
      });
      opCount++;

      // Items subcollection (to simulate the N+1 read target)
      for (var j = 0; j < chaptersPerDay; j++) {
        batch.set(entryRef.collection('items').doc('$j'), <String, dynamic>{});
        opCount++;
      }

      if (opCount > 400) {
        await batch.commit();
        batch = firestore.batch();
        opCount = 0;
      }
    }
    await batch.commit();

    // Benchmark
    final stopwatch = Stopwatch()..start();
    await service.memberDailyCompletion(groupId).first;
    stopwatch.stop();

    // deleted print statement to satisfy lints
  }, timeout: Timeout(Duration(minutes: 2)));
}
