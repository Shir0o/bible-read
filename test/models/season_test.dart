import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/season.dart';

void main() {
  group('Season', () {
    test('fromFirestore parses timestamps and metadata', () async {
      final firestore = FakeFirebaseFirestore();
      final start = DateTime(2024, 9, 1);
      final end = DateTime(2024, 10, 1);
      final ref = firestore.collection('seasons').doc('fall2024');
      await ref.set({
        'title': 'Fall 2024',
        'description': 'Autumn challenges',
        'startDate': Timestamp.fromDate(start),
        'endDate': Timestamp.fromDate(end),
        'bannerImageUrl': 'https://example.com/banner.png',
      });

      final snapshot = await ref.get();
      final season = Season.fromFirestore(snapshot);

      expect(season.id, 'fall2024');
      expect(season.title, 'Fall 2024');
      expect(season.startDate, start);
      expect(season.endDate, end);
      expect(season.bannerImageUrl, 'https://example.com/banner.png');

      final serialized = season.toFirestore();
      expect(serialized['title'], 'Fall 2024');
      expect(serialized['startDate'], isA<Timestamp>());
      expect(serialized['endDate'], isA<Timestamp>());
    });

    test('isActive returns true for dates inside the window', () {
      final season = Season(
        id: 'summer',
        title: 'Summer Season',
        description: 'Warm weather events',
        startDate: DateTime(2024, 6, 1),
        endDate: DateTime(2024, 6, 30),
      );

      expect(season.isActive(DateTime(2024, 6, 15)), isTrue);
      expect(season.isActive(DateTime(2024, 5, 31, 23, 59)), isFalse);
      expect(season.isActive(DateTime(2024, 7, 1)), isFalse);
    });
  });
}
