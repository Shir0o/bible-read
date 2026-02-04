import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Group', () {
    test('supports value equality', () {
      const g1 = Group(id: '1', name: 'N', ownerUid: 'o');
      const g2 = Group(id: '1', name: 'N', ownerUid: 'o');
      const g3 = Group(id: '2', name: 'N', ownerUid: 'o');

      expect(g1, equals(g2));
      expect(g1.hashCode, equals(g2.hashCode));
      expect(g1, isNot(equals(g3)));
    });

    test('fromFirestore parses data', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('groups').doc('g1').set({
        'name': 'Test',
        'ownerUid': 'u1',
        'memberCount': 3,
      });
      final doc = await firestore.collection('groups').doc('g1').get();

      final actual = Group.fromFirestore(doc);
      const expected = Group(
        id: 'g1',
        name: 'Test',
        ownerUid: 'u1',
        memberCount: 3,
      );

      expect(actual, equals(expected));
    });

    test('fromFirestore handles missing fields', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('groups').doc('g1').set({});
      final doc = await firestore.collection('groups').doc('g1').get();

      final actual = Group.fromFirestore(doc);
      const expected = Group(
        id: 'g1',
        name: '',
        ownerUid: '',
        memberCount: 0,
      );

      expect(actual, equals(expected));
    });

    test('toFirestore outputs expected map', () {
      const group = Group(
        id: 'g1',
        name: 'Test',
        ownerUid: 'u1',
        memberCount: 5,
        isPublic: true,
      );
      final map = group.toFirestore();
      expect(
        map,
        {
          'name': 'Test',
          'ownerUid': 'u1',
          'memberCount': 5,
          'isPublic': true,
        },
      );
    });
  });
}
