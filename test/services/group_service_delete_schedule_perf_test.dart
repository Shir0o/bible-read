import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  test('deleteSchedule benchmark', () async {
    final firestore = FakeFirebaseFirestore();
    final service = GroupService(firestore: firestore);

    const groupId = 'g1';
    final date = DateTime(2023, 1, 1);
    const members = 50; // Reduced to fit in a single batch during setup
    const itemsPerMember = 5;

    // Create group
    await firestore.collection('groups').doc(groupId).set({
      'name': 'Benchmark Group',
      'ownerUid': 'owner1',
      'memberCount': members,
    });

    // Create schedule
    final dateId = '2023-01-01';
    await firestore
        .collection('groups')
        .doc(groupId)
        .collection('schedule')
        .doc(dateId)
        .set({
      'date': Timestamp.fromDate(date),
      'chapters': List.generate(itemsPerMember, (i) => 'Chapter $i'),
    });

    // Populate progress entries
    final dateRef = firestore
        .collection('groups')
        .doc(groupId)
        .collection('progress')
        .doc(dateId);

    final batch = firestore.batch();
    for (var m = 0; m < members; m++) {
      final uid = 'user_$m';
      final entryRef = dateRef.collection('entries').doc(uid);
      batch.set(entryRef, {'count': itemsPerMember, 'uid': uid});

      for (var i = 0; i < itemsPerMember; i++) {
        batch.set(entryRef.collection('items').doc('item_$i'), {'done': true});
      }

      // Also add summary entries to be updated
      batch.set(
        firestore
            .collection('groups')
            .doc(groupId)
            .collection('progressSummary')
            .doc('data')
            .collection('entries')
            .doc(uid),
        {'completed': itemsPerMember, 'uid': uid},
      );
    }
    await batch.commit();

    final stopwatch = Stopwatch()..start();
    await service.deleteSchedule(groupId: groupId, date: date);
    stopwatch.stop();

    print('deleteSchedule took: ${stopwatch.elapsedMilliseconds}ms');

    // Verify deletion
    final scheduleDoc = await firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.schedule)
        .doc(dateId)
        .get();
    expect(scheduleDoc.exists, false);

    final entries = await dateRef.collection('entries').get();
    expect(entries.docs.isEmpty, true);

    final dateDoc = await dateRef.get();
    expect(dateDoc.exists, false);

    // Verify summaries updated (decremented)
    final summary = await firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection('progressSummary')
        .doc('data')
        .collection('entries')
        .doc('user_0')
        .get();
    expect(summary.data()?['completed'], 0);
  });
}
