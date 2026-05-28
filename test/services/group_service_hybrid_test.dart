import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/services/group_service.dart';

void main() {
  group('GroupService Hybrid Fetch', () {
    late FakeFirebaseFirestore firestore;
    late GroupService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = GroupService(firestore: firestore);
    });

    test(
      'recalcProgressForUserInGroup handles mix of indexed and legacy data',
      () async {
        final groupRef = firestore.collection('groups').doc('g1');
        await groupRef.set({'name': 'G', 'ownerUid': 'u1'});
        await groupRef.collection('members').doc('u1').set({
          'uid': 'u1',
          'role': 'owner',
        });

        // Date 1: Indexed (has groupId)
        final d1Ref = groupRef.collection('progress').doc('2024-01-01');
        await d1Ref.set({});
        await d1Ref.collection('entries').doc('u1').set({
          'count': 1,
          'uid': 'u1',
          'groupId': 'g1',
        });

        // Date 2: Legacy (missing groupId)
        final d2Ref = groupRef.collection('progress').doc('2024-01-02');
        await d2Ref.set({});
        await d2Ref.collection('entries').doc('u1').set({
          'count': 1,
          'uid': 'u1',
        });

        await service.recalcProgressForUserInGroup(groupId: 'g1', uid: 'u1');

        final summary = await groupRef
            .collection('progressSummary')
            .doc('data')
            .collection('entries')
            .doc('u1')
            .get();

        // Should find both: 1 + 1 = 2
        expect(summary.data()?['completed'], 2);

        // Verify repair: legacy document should now have groupId
        final d2Entry = await d2Ref.collection('entries').doc('u1').get();
        expect(d2Entry.data()?['groupId'], 'g1');
      },
    );

    test('leaveGroup cleans up legacy data', () async {
      final groupRef = firestore.collection('groups').doc('g1');
      await groupRef.set({'name': 'G', 'ownerUid': 'owner'});

      await groupRef.collection('members').doc('leaver').set({
        'uid': 'leaver',
        'role': 'member',
      });

      // Legacy progress (missing groupId)
      final d1Ref = groupRef.collection('progress').doc('2024-01-01');
      await d1Ref.set({});
      final entryRef = d1Ref.collection('entries').doc('leaver');
      await entryRef.set({'count': 1, 'uid': 'leaver'});
      await entryRef.collection('items').doc('item1').set({'done': true});

      await service.leaveGroup(groupId: 'g1', uid: 'leaver');

      final entrySnap = await entryRef.get();
      expect(entrySnap.exists, false);

      final itemSnap = await entryRef.collection('items').doc('item1').get();
      expect(itemSnap.exists, false);
    });
  });
}
