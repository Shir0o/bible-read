import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/services/friend_service.dart';

void main() {
  group('FriendService', () {
    late FakeFirebaseFirestore firestore;
    late FriendService friendService;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      friendService = FriendService(firestore: firestore);
    });

    test('pendingRequests handles non-string name gracefully', () async {
      final uid = 'user123';
      final fromUid = 'user456';

      await firestore
          .collection(FriendCollections.users)
          .doc(uid)
          .collection(FriendCollections.receivedRequests)
          .doc(fromUid)
          .set({'timestamp': Timestamp.now(), 'name': 123}); // Non-string name

      final requests = await friendService.pendingRequests(uid).first;
      expect(requests.length, 1);
      expect(requests.first.uid, fromUid);
      expect(requests.first.name, ''); // Should default to empty string
    });

    test('friends handles non-string name gracefully', () async {
      final uid = 'user123';
      final friendUid = 'user789';

      await firestore
          .collection(FriendCollections.users)
          .doc(uid)
          .collection(FriendCollections.friends)
          .doc(friendUid)
          .set({'timestamp': Timestamp.now(), 'name': true}); // Non-string name

      final friends = await friendService.friends(uid).first;
      expect(friends.length, 1);
      expect(friends.first.uid, friendUid);
      expect(friends.first.name, ''); // Should default to empty string
    });
  });
}
