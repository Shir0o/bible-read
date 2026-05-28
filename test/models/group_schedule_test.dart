import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group_schedule.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GroupSchedule', () {
    test('fromFirestore parses data', () async {
      final firestore = FakeFirebaseFirestore();
      final date = DateTime(2024, 1, 1);
      await firestore.collection('schedule').doc('2024-01-01').set({
        'date': Timestamp.fromDate(date),
        'chapters': ['Gen 1', 'Exo 2'],
      });
      final doc = await firestore
          .collection('schedule')
          .doc('2024-01-01')
          .get();

      final schedule = GroupSchedule.fromFirestore(doc);
      expect(schedule.date.toUtc(), date.toUtc());
      expect(schedule.chapters, ['Gen 1', 'Exo 2']);
    });

    test('fromFirestore handles malformed fields', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('schedule').doc('2024-01-02').set({
        'date': 'not a timestamp',
        'chapters': ['Gen 1', 2, true],
      });
      final doc = await firestore
          .collection('schedule')
          .doc('2024-01-02')
          .get();

      final schedule = GroupSchedule.fromFirestore(doc);
      expect(schedule.date.toUtc(), DateTime(2024, 1, 2).toUtc());
      expect(schedule.chapters, ['Gen 1']);
    });

    test('toFirestore outputs expected map', () {
      final date = DateTime.utc(2024, 1, 1);
      final schedule = GroupSchedule(date: date, chapters: const ['Gen 1']);
      final map = schedule.toFirestore();
      expect(map['date'], Timestamp.fromDate(date));
      expect(map['chapters'], ['Gen 1']);
    });
  });
}
