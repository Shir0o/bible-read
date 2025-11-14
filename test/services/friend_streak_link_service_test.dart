import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/friend_streak_link_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FriendStreakLinkService', () {
    late FakeFirebaseFirestore firestore;
    late FriendStreakLinkService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = FriendStreakLinkService(firestore: firestore);
    });

    Future<void> seedLink({
      required String owner,
      required String partner,
      int currentStreak = 0,
      DateTime? lastUser,
      DateTime? lastPartner,
      DateTime? partnerLastUser,
      DateTime? partnerLastPartner,
    }) async {
      Future<void> writeDoc({
        required String uid,
        required String peer,
        DateTime? userCovered,
        DateTime? partnerCovered,
        int streak = 0,
      }) async {
        await firestore
            .collection(FriendCollections.users)
            .doc(uid)
            .collection(FriendCollections.friendStreakLinks)
            .doc(peer)
            .set({
          'status': 'active',
          'partnerUid': peer,
          'initiatedBy': uid,
          'currentStreak': streak,
          if (userCovered != null)
            'lastUserCovered': Timestamp.fromDate(userCovered),
          if (partnerCovered != null)
            'lastPartnerCovered': Timestamp.fromDate(partnerCovered),
          'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
          'updatedAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
        });
      }

      await writeDoc(
        uid: owner,
        peer: partner,
        userCovered: lastUser,
        partnerCovered: lastPartner,
        streak: currentStreak,
      );
      await writeDoc(
        uid: partner,
        peer: owner,
        userCovered: partnerLastUser ?? lastPartner,
        partnerCovered: partnerLastPartner ?? lastUser,
        streak: currentStreak,
      );
    }

    test('recordCoverage ignores null dates and grace coverage', () async {
      await seedLink(owner: 'a', partner: 'b');

      await service.recordCoverage('a', null, false);
      await service.recordCoverage('a', DateTime(2024, 1, 1), true);

      final ownerDoc = await firestore
          .collection('users')
          .doc('a')
          .collection(FriendCollections.friendStreakLinks)
          .doc('b')
          .get();
      expect(ownerDoc.data()?['lastUserCovered'], isNull);
    });

    test('recordCoverage updates local streak data for the first reader',
        () async {
      final previousDay = DateTime(2024, 1, 1);
      await seedLink(
        owner: 'a',
        partner: 'b',
        currentStreak: 3,
        lastUser: previousDay,
        lastPartner: previousDay,
      );

      final today = DateTime(2024, 1, 2);
      await service.recordCoverage('a', today, false);

      final ownerDoc = await firestore
          .collection('users')
          .doc('a')
          .collection(FriendCollections.friendStreakLinks)
          .doc('b')
          .get();
      final partnerDoc = await firestore
          .collection('users')
          .doc('b')
          .collection(FriendCollections.friendStreakLinks)
          .doc('a')
          .get();

      expect(ownerDoc.data()?['currentStreak'], 1);
      expect(ownerDoc.data()?['streakBrokenOn'], isNotNull);
      expect(partnerDoc.data()?['currentStreak'], 3);
      expect(
        (partnerDoc.data()?['lastPartnerCovered'] as Timestamp?)?.toDate(),
        today,
      );
    });

    test('recordCoverage increments streak when both covered the same day',
        () async {
      final today = DateTime(2024, 1, 10);
      final previous = today.subtract(const Duration(days: 1));
      await seedLink(
        owner: 'a',
        partner: 'b',
        currentStreak: 5,
        lastUser: previous,
        lastPartner: today,
        partnerLastUser: today,
        partnerLastPartner: previous,
      );

      await service.recordCoverage('a', today, false);

      final ownerDoc = await firestore
          .collection('users')
          .doc('a')
          .collection(FriendCollections.friendStreakLinks)
          .doc('b')
          .get();
      final partnerDoc = await firestore
          .collection('users')
          .doc('b')
          .collection(FriendCollections.friendStreakLinks)
          .doc('a')
          .get();

      expect(ownerDoc.data()?['currentStreak'], 6);
      expect(ownerDoc.data()?['streakBrokenOn'], isNull);
      expect(
        (ownerDoc.data()?['lastUserCovered'] as Timestamp?)?.toDate(),
        today,
      );
      expect(partnerDoc.data()?['currentStreak'], 6);
      expect(partnerDoc.data()?['streakBrokenOn'], isNull);
    });

    test('recordCoverage tolerates missing partner documents', () async {
      await firestore
          .collection('users')
          .doc('solo')
          .collection(FriendCollections.friendStreakLinks)
          .doc('missing')
          .set({
        'status': 'active',
        'partnerUid': 'missing',
        'currentStreak': 0,
        'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
      });

      await expectLater(
        service.recordCoverage('solo', DateTime(2024, 1, 5), false),
        completes,
      );
    });
  });
}
