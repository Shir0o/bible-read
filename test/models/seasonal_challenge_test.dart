import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/seasonal_challenge.dart';
import 'package:bible_read/models/seasonal_reward.dart';

void main() {
  group('SeasonalChallenge', () {
    test('fromFirestore parses reward metadata', () async {
      final firestore = FakeFirebaseFirestore();
      final ref = firestore
          .collection('seasons')
          .doc('winter')
          .collection('challenges')
          .doc('read');
      await ref.set({
        'seasonId': 'winter',
        'title': 'Read five chapters',
        'description': 'Read five chapters during winter',
        'metric': 'chapters',
        'goal': 5,
        'dailyCap': 3,
        'repeatable': false,
        'reward': {
          'id': 'snowflake',
          'type': 'badge',
          'title': 'Snowflake Badge',
          'description': 'Awarded for reading five chapters in winter',
          'iconUrl': 'https://example.com/snowflake.png',
          'amount': 1,
        },
      });

      final snapshot = await ref.get();
      final challenge = SeasonalChallenge.fromFirestore('winter', snapshot);

      expect(challenge.id, 'read');
      expect(challenge.goal, 5);
      expect(challenge.dailyCap, 3);
      expect(challenge.reward, isA<SeasonalReward>());
      expect(challenge.reward?.title, 'Snowflake Badge');

      final serialized = challenge.toFirestore();
      expect(serialized['goal'], 5);
      expect(serialized['reward'], isA<Map<String, dynamic>>());
      expect(serialized['reward']['title'], 'Snowflake Badge');
    });
  });
}
