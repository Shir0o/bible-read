import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/seasonal_reward.dart';

void main() {
  group('SeasonalReward', () {
    test('fromFirestore reads fields and converts numbers', () async {
      final firestore = FakeFirebaseFirestore();
      final ref = firestore
          .collection('seasons')
          .doc('spring')
          .collection('rewards')
          .doc('badge');
      await ref.set({
        'type': 'badge',
        'title': 'Spring Badge',
        'description': 'Awarded for finishing the spring challenge',
        'iconUrl': 'https://example.com/badge.png',
        'amount': 1.0,
      });

      final snapshot = await ref.get();
      final reward = SeasonalReward.fromFirestore(snapshot);

      expect(reward.id, 'badge');
      expect(reward.title, 'Spring Badge');
      expect(reward.type, 'badge');
      expect(reward.amount, 1);
      expect(reward.iconUrl, 'https://example.com/badge.png');

      final serialized = reward.toFirestore();
      expect(serialized['id'], 'badge');
      expect(serialized['type'], 'badge');
      expect(serialized['amount'], 1);
    });

    test('fromMap provides defaults when fields are missing', () {
      final reward = SeasonalReward.fromMap({
        'title': 'Mystery Gift',
        'amount': '25',
      });

      expect(reward.title, 'Mystery Gift');
      expect(reward.amount, 25);
      expect(reward.type, '');
    });
  });
}
