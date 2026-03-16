import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/services/group_service.dart';

void main() {
  test('deleteGroup benchmark', () async {
    final firestore = FakeFirebaseFirestore();
    final service = GroupService(firestore: firestore);

    const groupId = 'g1';
    const ownerUid = 'owner1';
    const days = 100; // 100 days of history
    const members = 20; // 20 members

    // Create group
    await firestore.collection('groups').doc(groupId).set({
      'name': 'Benchmark Group',
      'ownerUid': ownerUid,
      'memberCount': members,
    });

    // Populate Data
    // deleted print statement to satisfy lints
    var batch = firestore.batch();
    int opCount = 0;

    // Members
    for (var m = 0; m < members; m++) {
      batch.set(
          firestore
              .collection('groups')
              .doc(groupId)
              .collection('members')
              .doc('user_$m'),
          {'uid': 'user_$m', 'role': 'member'});
      opCount++;
    }

    // Progress
    for (var d = 0; d < days; d++) {
      final dateId =
          '2023-01-${d.toString().padLeft(2, '0')}'; // Simplified dateId
      final dateRef = firestore
          .collection('groups')
          .doc(groupId)
          .collection('progress')
          .doc(dateId);

      batch.set(dateRef, {'id': dateId});
      opCount++;

      for (var m = 0; m < members; m++) {
        final entryRef = dateRef.collection('entries').doc('user_$m');
        batch.set(entryRef, {'count': 1, 'done': true});
        opCount++;

        // Also add items subcollection to make it realistic
        batch.set(entryRef.collection('items').doc('item1'), {'done': true});
        opCount++;
      }

      if (opCount > 400) {
        await batch.commit();
        batch = firestore.batch();
        opCount = 0;
      }
    }
    if (opCount > 0) {
      await batch.commit();
    }

    // deleted print statement to satisfy lints

    final stopwatch = Stopwatch()..start();
    await service.deleteGroup(groupId: groupId, ownerUid: ownerUid);
    stopwatch.stop();

    // deleted print statement to satisfy lints

    // Verify everything is deleted
    final groupDoc = await firestore.collection('groups').doc(groupId).get();
    expect(groupDoc.exists, false);

    final progressDocs = await firestore
        .collection('groups')
        .doc(groupId)
        .collection('progress')
        .get();
    expect(progressDocs.docs.isEmpty, true);
  });
}
