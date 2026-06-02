import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/notification_service.dart'
    show NotificationService, NotificationCollections;
import 'package:bible_read/models/notification_preferences.dart';

void main() {
  group('FriendService', () {
    late FakeFirebaseFirestore firestore;
    late FriendService friendService;
    late Map<String, dynamic>? lastAcceptArgs;
    late bool acceptCalled;
    late Map<String, dynamic>? lastDeleteArgs;
    late bool deleteCalled;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      acceptCalled = false;
      lastAcceptArgs = null;
      deleteCalled = false;
      lastDeleteArgs = null;
      friendService = FriendService(
        firestore: firestore,
        notificationService: NotificationService(firestore: firestore),
        acceptFriendRequestFn: ({
          required String fromUid,
          required String toUid,
          required String fromName,
          required String toName,
        }) async {
          acceptCalled = true;
          lastAcceptArgs = {
            'fromUid': fromUid,
            'toUid': toUid,
            'fromName': fromName,
            'toName': toName,
          };
          await firestore
              .collection(FriendCollections.users)
              .doc(fromUid)
              .collection(FriendCollections.sentRequests)
              .doc(toUid)
              .delete();
          await firestore
              .collection(FriendCollections.users)
              .doc(toUid)
              .collection(FriendCollections.receivedRequests)
              .doc(fromUid)
              .delete();
          await firestore
              .collection(FriendCollections.users)
              .doc(fromUid)
              .collection(FriendCollections.friends)
              .doc(toUid)
              .set({'timestamp': Timestamp.now(), 'name': toName});
          await firestore
              .collection(FriendCollections.users)
              .doc(toUid)
              .collection(FriendCollections.friends)
              .doc(fromUid)
              .set({'timestamp': Timestamp.now(), 'name': fromName});
        },
        deleteFriendRequestPairFn: (
            {required String fromUid, required String toUid}) async {
          deleteCalled = true;
          lastDeleteArgs = {'fromUid': fromUid, 'toUid': toUid};
          await firestore
              .collection(FriendCollections.users)
              .doc(fromUid)
              .collection(FriendCollections.sentRequests)
              .doc(toUid)
              .delete();
          await firestore
              .collection(FriendCollections.users)
              .doc(toUid)
              .collection(FriendCollections.receivedRequests)
              .doc(fromUid)
              .delete();
        },
      );
    });

    group('sendFriendRequest', () {
      test('should create sent and received requests', () async {
        const fromUid = 'userA';
        const fromName = 'User A';
        const toUid = 'userB';

        await friendService.sendFriendRequest(
          fromUid: fromUid,
          fromName: fromName,
          toUid: toUid,
        );

        // Verify sent request
        final sentRequestDoc = await firestore
            .collection(FriendCollections.users)
            .doc(fromUid)
            .collection(FriendCollections.sentRequests)
            .doc(toUid)
            .get();
        expect(sentRequestDoc.exists, isTrue);
        expect(sentRequestDoc.data()?.containsKey('timestamp'), isTrue);

        // Verify received request
        final receivedRequestDoc = await firestore
            .collection(FriendCollections.users)
            .doc(toUid)
            .collection(FriendCollections.receivedRequests)
            .doc(fromUid)
            .get();
        expect(receivedRequestDoc.exists, isTrue);
        expect(receivedRequestDoc.data()?.containsKey('timestamp'), isTrue);
        expect(receivedRequestDoc.data()?['name'], fromName);
      });

      test('creates notification document for recipient', () async {
        const fromUid = 'userA';
        const fromName = 'User A';
        const toUid = 'userB';

        await friendService.sendFriendRequest(
          fromUid: fromUid,
          fromName: fromName,
          toUid: toUid,
        );

        final notifSnap = await firestore
            .collection(NotificationCollections.users)
            .doc(toUid)
            .collection(NotificationCollections.notifications)
            .get();
        expect(notifSnap.docs.length, 1);
        final data = notifSnap.docs.first.data();
        expect(data['type'], NotificationType.friendRequest.name);
        expect(data['fromUid'], fromUid);
      });

      test('throws ArgumentError when fromUid equals toUid', () async {
        const uid = 'userA';
        expect(
          () => friendService.sendFriendRequest(
            fromUid: uid,
            fromName: 'User A',
            toUid: uid,
          ),
          throwsArgumentError,
        );
      });

      test('should overwrite existing requests on duplicate send', () async {
        const fromUid = 'userA';
        const fromName = 'User A';
        const toUid = 'userB';

        await firestore
            .collection(FriendCollections.users)
            .doc(fromUid)
            .collection(FriendCollections.sentRequests)
            .doc(toUid)
            .set({'timestamp': Timestamp(0, 0)});

        await friendService.sendFriendRequest(
          fromUid: fromUid,
          fromName: fromName,
          toUid: toUid,
        );

        final sentRequestDoc = await firestore
            .collection(FriendCollections.users)
            .doc(fromUid)
            .collection(FriendCollections.sentRequests)
            .doc(toUid)
            .get();
        expect(sentRequestDoc.exists, isTrue);
        expect(
          (sentRequestDoc.data()?['timestamp'] as Timestamp).seconds,
          isNot(0),
        );
      });
    });

    group('sendFriendRequestByEmail', () {
      test('should look up user by email and create request', () async {
        const fromUid = 'userA';
        const fromName = 'User A';
        const toUid = 'userB';
        const toEmail = 'b@example.com';

        await firestore.collection(FriendCollections.users).doc(toUid).set({
          'email': toEmail,
        });

        await friendService.sendFriendRequestByEmail(
          fromUid: fromUid,
          fromName: fromName,
          toEmail: toEmail,
        );

        final sentRequestDoc = await firestore
            .collection(FriendCollections.users)
            .doc(fromUid)
            .collection(FriendCollections.sentRequests)
            .doc(toUid)
            .get();
        final receivedRequestDoc = await firestore
            .collection(FriendCollections.users)
            .doc(toUid)
            .collection(FriendCollections.receivedRequests)
            .doc(fromUid)
            .get();

        expect(sentRequestDoc.exists, isTrue);
        expect(receivedRequestDoc.exists, isTrue);
      });

      test('should throw error when email not found', () async {
        expect(
          () => friendService.sendFriendRequestByEmail(
            fromUid: 'a',
            fromName: 'Alice',
            toEmail: 'unknown@example.com',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('looks up email case-insensitively', () async {
        const fromUid = 'userA';
        const fromName = 'User A';
        const toUid = 'userB';

        await firestore.collection(FriendCollections.users).doc(toUid).set({
          'email': 'b@example.com',
        });

        await friendService.sendFriendRequestByEmail(
          fromUid: fromUid,
          fromName: fromName,
          toEmail: 'B@Example.Com',
        );

        final sent = await firestore
            .collection(FriendCollections.users)
            .doc(fromUid)
            .collection(FriendCollections.sentRequests)
            .doc(toUid)
            .get();
        expect(sent.exists, isTrue);
      });
    });

    group('acceptFriendRequest', () {
      test('should delete requests and add friends', () async {
        const currentUid = 'userB';
        const currentName = 'User B';
        const fromUid = 'userA';
        const fromName = 'User A';

        // Set up initial state: pending friend request
        await firestore
            .collection(FriendCollections.users)
            .doc(fromUid)
            .collection(FriendCollections.sentRequests)
            .doc(currentUid)
            .set({'timestamp': Timestamp.now()});
        await firestore
            .collection(FriendCollections.users)
            .doc(currentUid)
            .collection(FriendCollections.receivedRequests)
            .doc(fromUid)
            .set({'timestamp': Timestamp.now(), 'name': fromName});

        await friendService.acceptFriendRequest(
          currentUid: currentUid,
          currentName: currentName,
          fromUid: fromUid,
          fromName: fromName,
        );

        // Verify requests are deleted
        final sentRequestDoc = await firestore
            .collection(FriendCollections.users)
            .doc(fromUid)
            .collection(FriendCollections.sentRequests)
            .doc(currentUid)
            .get();
        expect(sentRequestDoc.exists, isFalse);

        final receivedRequestDoc = await firestore
            .collection(FriendCollections.users)
            .doc(currentUid)
            .collection(FriendCollections.receivedRequests)
            .doc(fromUid)
            .get();
        expect(receivedRequestDoc.exists, isFalse);

        // Verify friends are added
        final friendDocA = await firestore
            .collection(FriendCollections.users)
            .doc(fromUid)
            .collection(FriendCollections.friends)
            .doc(currentUid)
            .get();
        expect(friendDocA.exists, isTrue);
        expect(friendDocA.data()?.containsKey('timestamp'), isTrue);
        expect(friendDocA.data()?['name'], currentName);

        final friendDocB = await firestore
            .collection(FriendCollections.users)
            .doc(currentUid)
            .collection(FriendCollections.friends)
            .doc(fromUid)
            .get();
        expect(friendDocB.exists, isTrue);
        expect(friendDocB.data()?.containsKey('timestamp'), isTrue);
        expect(friendDocB.data()?['name'], fromName);

        expect(acceptCalled, isTrue);
        expect(lastAcceptArgs, {
          'fromUid': fromUid,
          'toUid': currentUid,
          'fromName': fromName,
          'toName': currentName,
        });
      });

      test('accepting non-existent request should still complete', () async {
        const currentUid = 'userB';
        const currentName = 'User B';
        const fromUid = 'userA';
        const fromName = 'User A';

        await friendService.acceptFriendRequest(
          currentUid: currentUid,
          currentName: currentName,
          fromUid: fromUid,
          fromName: fromName,
        );

        final friendDoc = await firestore
            .collection(FriendCollections.users)
            .doc(currentUid)
            .collection(FriendCollections.friends)
            .doc(fromUid)
            .get();
        expect(friendDoc.exists, isTrue);

        expect(acceptCalled, isTrue);
      });
    });

    group('declineFriendRequest', () {
      test('should delete sent and received requests', () async {
        const currentUid = 'userB';
        const fromUid = 'userA';
        const fromName = 'User A';

        // Set up initial state: pending friend request
        await firestore
            .collection(FriendCollections.users)
            .doc(fromUid)
            .collection(FriendCollections.sentRequests)
            .doc(currentUid)
            .set({'timestamp': Timestamp.now()});
        await firestore
            .collection(FriendCollections.users)
            .doc(currentUid)
            .collection(FriendCollections.receivedRequests)
            .doc(fromUid)
            .set({'timestamp': Timestamp.now(), 'name': fromName});

        await friendService.declineFriendRequest(
          currentUid: currentUid,
          fromUid: fromUid,
        );

        // Verify requests are deleted
        final sentRequestDoc = await firestore
            .collection(FriendCollections.users)
            .doc(fromUid)
            .collection(FriendCollections.sentRequests)
            .doc(currentUid)
            .get();
        expect(sentRequestDoc.exists, isFalse);

        final receivedRequestDoc = await firestore
            .collection(FriendCollections.users)
            .doc(currentUid)
            .collection(FriendCollections.receivedRequests)
            .doc(fromUid)
            .get();
        expect(receivedRequestDoc.exists, isFalse);

        expect(deleteCalled, isTrue);
        expect(lastDeleteArgs, {'fromUid': fromUid, 'toUid': currentUid});
      });

      test('declining non-existent request should still complete', () async {
        const currentUid = 'userB';
        const fromUid = 'userA';

        await friendService.declineFriendRequest(
          currentUid: currentUid,
          fromUid: fromUid,
        );

        // No exception thrown
        final sentDoc = await firestore
            .collection(FriendCollections.users)
            .doc(fromUid)
            .collection(FriendCollections.sentRequests)
            .doc(currentUid)
            .get();
        expect(sentDoc.exists, isFalse);

        expect(deleteCalled, isTrue);
      });
    });

    group('nudgeFriend', () {
      test('calls Cloud Function with expected arguments', () async {
        const currentUid = 'userA';
        const friendUid = 'userB';
        const currentName = 'Alice';
        bool called = false;
        Map<String, String>? lastArgs;

        friendService = FriendService(
          firestore: firestore,
          notificationService: NotificationService(firestore: firestore),
          sendNudgeNotificationFn: ({
            required String fromUid,
            required String toUid,
            required String fromName,
          }) async {
            called = true;
            lastArgs = {
              'fromUid': fromUid,
              'toUid': toUid,
              'fromName': fromName,
            };
            return NudgeResult.sent;
          },
        );

        final result = await friendService.nudgeFriend(
          currentUid: currentUid,
          friendUid: friendUid,
          currentName: currentName,
        );

        expect(called, isTrue);
        expect(lastArgs, {
          'fromUid': currentUid,
          'toUid': friendUid,
          'fromName': currentName,
        });
        expect(result, NudgeResult.sent);
      });
    });

    group('nudgedToday', () {
      test('emits set of friend UIDs nudged today', () async {
        const uid = 'userA';
        const todayUid = 'friend1';
        const yesterdayUid = 'friend2';
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day);

        await firestore
            .collection(FriendCollections.users)
            .doc(uid)
            .collection(FriendCollections.nudges)
            .doc(todayUid)
            .set({
          'timestamp': Timestamp.fromDate(
            start.add(const Duration(hours: 1)),
          ),
        });

        await firestore
            .collection(FriendCollections.users)
            .doc(uid)
            .collection(FriendCollections.nudges)
            .doc(yesterdayUid)
            .set({
          'timestamp': Timestamp.fromDate(
            start.subtract(const Duration(days: 1)),
          ),
        });

        final result = await friendService.nudgedToday(uid).first;
        expect(result, {todayUid});
      });
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

    test('pendingRequests skips document with ID "init"', () async {
      final uid = 'userABC';
      const fromUid = 'userDEF';

      // Document that should be ignored
      await firestore
          .collection(FriendCollections.users)
          .doc(uid)
          .collection(FriendCollections.receivedRequests)
          .doc('init')
          .set({'timestamp': Timestamp.now(), 'name': 'Init'});

      // Valid friend request
      await firestore
          .collection(FriendCollections.users)
          .doc(uid)
          .collection(FriendCollections.receivedRequests)
          .doc(fromUid)
          .set({'timestamp': Timestamp.now(), 'name': 'Bob'});

      final requests = await friendService.pendingRequests(uid).first;
      expect(requests.length, 1);
      expect(requests.first.uid, fromUid);
    });

    test('friends skips document with ID "init"', () async {
      final uid = 'userABC';
      const friendUid = 'userXYZ';

      // Document that should be ignored
      await firestore
          .collection(FriendCollections.users)
          .doc(uid)
          .collection(FriendCollections.friends)
          .doc('init')
          .set({'timestamp': Timestamp.now(), 'name': 'Init'});

      // Valid friend
      await firestore
          .collection(FriendCollections.users)
          .doc(uid)
          .collection(FriendCollections.friends)
          .doc(friendUid)
          .set({'timestamp': Timestamp.now(), 'name': 'Alice'});

      final friends = await friendService.friends(uid).first;
      expect(friends.length, 1);
      expect(friends.first.uid, friendUid);
    });
  });
}
