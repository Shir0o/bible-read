import 'package:cloud_firestore/cloud_firestore.dart';

/// Names of Firestore collections used for friend features.
class FriendCollections {
  FriendCollections._();

  /// top-level users collection
  static const String users = 'users';

  /// Sub-collection containing requests the user has sent.
  static const String sentRequests = 'friendRequestsSent';

  /// Sub-collection containing requests the user has received.
  static const String receivedRequests = 'friendRequestsReceived';

  /// Sub-collection containing a user's friends.
  static const String friends = 'friends';
}

/// Represents a pending friend request.
class FriendRequest {
  /// UID of the user who sent the request.
  final String uid;

  /// Display name of the sender.
  final String name;

  /// Creates a [FriendRequest].
  const FriendRequest({required this.uid, required this.name});
}

/// Represents an existing friend.
class Friend {
  /// UID of the friend.
  final String uid;

  /// Display name of the friend.
  final String name;

  /// Creates a [Friend].
  const Friend({required this.uid, required this.name});
}

/// Provides helper methods for friend request CRUD operations.
class FriendService {
  /// Firestore instance used for database operations.
  final FirebaseFirestore firestore;

  /// Creates a [FriendService] using [FirebaseFirestore.instance] by default.
  FriendService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  /// Send a friend request from [fromUid] to [toUid].
  Future<void> sendFriendRequest({
    required String fromUid,
    required String fromName,
    required String toUid,
  }) async {
    if (fromUid == toUid) {
      throw ArgumentError('Cannot send a friend request to yourself.');
    }
    final now = Timestamp.now();
    final batch = firestore.batch();
    batch.set(
      firestore
          .collection(FriendCollections.users)
          .doc(fromUid)
          .collection(FriendCollections.sentRequests)
          .doc(toUid),
      {'timestamp': now},
    );
    batch.set(
      firestore
          .collection(FriendCollections.users)
          .doc(toUid)
          .collection(FriendCollections.receivedRequests)
          .doc(fromUid),
      {'timestamp': now, 'name': fromName},
    );
    await batch.commit();
  }

  /// Accept a friend request sent by [fromUid] to [currentUid].
  Future<void> acceptFriendRequest({
    required String currentUid,
    required String fromUid,
    required String currentName,
    required String fromName,
  }) async {
    final batch = firestore.batch();
    final fromRef = firestore.collection(FriendCollections.users).doc(fromUid);
    final toRef = firestore.collection(FriendCollections.users).doc(currentUid);
    batch.delete(
        fromRef.collection(FriendCollections.sentRequests).doc(currentUid));
    batch.delete(
        toRef.collection(FriendCollections.receivedRequests).doc(fromUid));
    batch.set(
      fromRef.collection(FriendCollections.friends).doc(currentUid),
      {'timestamp': Timestamp.now(), 'name': currentName},
    );
    batch.set(
      toRef.collection(FriendCollections.friends).doc(fromUid),
      {'timestamp': Timestamp.now(), 'name': fromName},
    );
    await batch.commit();
  }

  /// Decline a friend request sent by [fromUid] to [currentUid].
  Future<void> declineFriendRequest({
    required String currentUid,
    required String fromUid,
  }) async {
    final batch = firestore.batch();
    batch.delete(firestore
        .collection(FriendCollections.users)
        .doc(fromUid)
        .collection(FriendCollections.sentRequests)
        .doc(currentUid));
    batch.delete(firestore
        .collection(FriendCollections.users)
        .doc(currentUid)
        .collection(FriendCollections.receivedRequests)
        .doc(fromUid));
    await batch.commit();
  }

  /// Stream of pending friend requests for [uid].
  Stream<List<FriendRequest>> pendingRequests(String uid) {
    return firestore
        .collection(FriendCollections.users)
        .doc(uid)
        .collection(FriendCollections.receivedRequests)
        .snapshots()
        .map((s) => s.docs.where((d) => d.id != 'init').map((d) {
              final data = d.data();
              return FriendRequest(
                uid: d.id,
                name: data['name'] is String ? data['name'] : '',
              );
            }).toList());
  }

  /// Stream of friends for [uid].
  Stream<List<Friend>> friends(String uid) {
    return firestore
        .collection(FriendCollections.users)
        .doc(uid)
        .collection(FriendCollections.friends)
        .snapshots()
        .map((s) => s.docs.where((d) => d.id != 'init').map((d) {
              final data = d.data();
              return Friend(
                uid: d.id,
                name: data['name'] is String ? data['name'] : '',
              );
            }).toList());
  }
}
