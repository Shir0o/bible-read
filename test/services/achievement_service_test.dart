import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bible_read/services/achievement_service.dart';
import 'package:bible_read/models/achievement.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('AchievementService', () {
    late FakeFirebaseFirestore firestore;
    late AchievementService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = AchievementService(firestore: firestore);
    });

    test('unlockAchievement writes document', () async {
      const uid = 'user1';
      final achievement = Achievement(
        id: 'firstReader',
        title: 'First Reader',
        type: 'first',
        dateUnlocked: DateTime(2024, 1, 1),
      );

      await service.unlockAchievement(uid, achievement);

      final doc = await firestore
          .collection('users')
          .doc(uid)
          .collection(AchievementService.achievementsCollection)
          .doc(achievement.id)
          .get();
      expect(doc.exists, isTrue);
      final data = doc.data()!;
      expect(data['title'], achievement.title);
      expect(data['type'], achievement.type);
      expect((data['dateUnlocked'] as Timestamp).toDate(),
          achievement.dateUnlocked);
    });

    test('achievements stream returns list of Achievement', () async {
      const uid = 'user2';
      final collection = firestore
          .collection('users')
          .doc(uid)
          .collection(AchievementService.achievementsCollection);

      await collection.doc('a1').set({
        'title': 'Old',
        'type': 't1',
        'dateUnlocked': Timestamp.fromDate(DateTime(2023, 1, 1)),
      });
      await collection.doc('a2').set({
        'title': 'New',
        'type': 't2',
        'dateUnlocked': Timestamp.fromDate(DateTime(2024, 1, 1)),
      });

      final list = await service.achievements(uid).first;
      expect(list.length, 2);
      expect(list.first.id, 'a2'); // Ordered by dateUnlocked descending
      expect(list.first.title, 'New');
      expect(list.last.id, 'a1');
      expect(list.last.type, 't1');
    });

    test('achievements stream handles missing dateUnlocked', () async {
      const uid = 'userMissing';
      final collection = firestore
          .collection('users')
          .doc(uid)
          .collection(AchievementService.achievementsCollection);

      await collection.doc('a1').set({
        'title': 'NoDate',
        'type': 't1',
      });

      final list = await service.achievements(uid).first;
      expect(list.length, 1);
      final now = DateTime.now();
      expect(now.difference(list.first.dateUnlocked).inSeconds < 5, isTrue);
    });

    test('achievements stream handles invalid dateUnlocked type', () async {
      const uid = 'userInvalid';
      final collection = firestore
          .collection('users')
          .doc(uid)
          .collection(AchievementService.achievementsCollection);

      await collection.doc('a1').set({
        'title': 'Bad',
        'type': 't1',
        'dateUnlocked': 'not a timestamp',
      });

      final list = await service.achievements(uid).first;
      expect(list.length, 1);
      final now = DateTime.now();
      expect(now.difference(list.first.dateUnlocked).inSeconds < 5, isTrue);
    });

    test('unlockedAchievementIds stream emits set of ids', () async {
      const uid = 'user3';
      final collection = firestore
          .collection('users')
          .doc(uid)
          .collection(AchievementService.achievementsCollection);

      await collection.doc('id1').set({
        'title': 'One',
        'type': 't1',
        'dateUnlocked': Timestamp.fromDate(DateTime.now()),
      });
      await collection.doc('id2').set({
        'title': 'Two',
        'type': 't2',
        'dateUnlocked': Timestamp.fromDate(DateTime.now()),
      });

      final ids = await service.unlockedAchievementIds(uid).first;
      expect(ids, {'id1', 'id2'});
    });
  });
}
