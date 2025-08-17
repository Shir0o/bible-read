import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Group', () {
    test('fromFirestore parses data', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('groups').doc('g1').set({
        'name': 'Test',
        'ownerUid': 'u1',
        'isPublic': false,
      });
      final doc = await firestore.collection('groups').doc('g1').get();

      final group = Group.fromFirestore(doc);
      expect(group.id, 'g1');
      expect(group.name, 'Test');
      expect(group.ownerUid, 'u1');
      expect(group.isPublic, isFalse);
    });

    test('fromFirestore handles missing fields', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('groups').doc('g1').set({});
      final doc = await firestore.collection('groups').doc('g1').get();

      final group = Group.fromFirestore(doc);
      expect(group.name, '');
      expect(group.ownerUid, '');
      expect(group.isPublic, isTrue);
    });

    test('toFirestore outputs expected map', () {
      const group = Group(
        id: 'g1',
        name: 'Test',
        ownerUid: 'u1',
        isPublic: false,
      );
      final map = group.toFirestore();
      expect(map, {'name': 'Test', 'ownerUid': 'u1', 'isPublic': false});
    });
  });
}
