import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/comment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Comment', () {
    test('fromFirestore parses data', () async {
      final firestore = FakeFirebaseFirestore();
      final date = DateTime(2024, 1, 1);
      await firestore.collection('comments').doc('c1').set({
        'uid': 'u1',
        'authorName': 'Alice',
        'message': 'Hi',
        'timestamp': Timestamp.fromDate(date),
      });
      final doc = await firestore.collection('comments').doc('c1').get();

      final comment = Comment.fromFirestore(doc);
      expect(comment.id, 'c1');
      expect(comment.uid, 'u1');
      expect(comment.authorName, 'Alice');
      expect(comment.message, 'Hi');
      expect(comment.timestamp.toUtc(), date.toUtc());
    });

    test('fromFirestore handles missing fields', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('comments').doc('c1').set({});
      final doc = await firestore.collection('comments').doc('c1').get();

      final comment = Comment.fromFirestore(doc);
      expect(comment.uid, '');
      expect(comment.authorName, '');
      expect(comment.message, '');
      expect(comment.timestamp, isA<DateTime>());
    });

    test('toFirestore outputs expected map', () {
      final date = DateTime(2024, 1, 1);
      final comment = Comment(
        id: 'c1',
        uid: 'u1',
        authorName: 'Alice',
        message: 'Hi',
        timestamp: date,
      );
      final map = comment.toFirestore();
      expect(map, {
        'uid': 'u1',
        'authorName': 'Alice',
        'message': 'Hi',
        'timestamp': Timestamp.fromDate(date),
      });
    });
  });
}
