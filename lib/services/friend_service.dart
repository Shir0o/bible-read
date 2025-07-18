import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

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

/// Signature for calling the `acceptFriendRequest` Cloud Function.
typedef AcceptFriendRequestFn = Future<void> Function({
  required String fromUid,
  required String toUid,
  required String fromName,
  required String toName,
});

/// Signature for calling the `deleteFriendRequestPair` Cloud Function.
typedef DeleteFriendRequestPairFn = Future<void> Function({
  required String fromUid,
  required String toUid,
});

/// Provides helper methods for friend request CRUD operations.
class FriendService {
  /// Firestore instance used for database operations.
  final FirebaseFirestore firestore;

  /// Function used to invoke the accept friend request Cloud Function.
  final AcceptFriendRequestFn _acceptFn;

  /// Function used to invoke the delete friend request pair Cloud Function.
  final DeleteFriendRequestPairFn _deleteFn;

  /// Creates a [FriendService] using [FirebaseFirestore.instance] by default.
  FriendService({
    FirebaseFirestore? firestore,
    AcceptFriendRequestFn? acceptFriendRequestFn,
    DeleteFriendRequestPairFn? deleteFriendRequestPairFn,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        _acceptFn = acceptFriendRequestFn ?? _defaultAcceptFriendRequest,
        _deleteFn =
            deleteFriendRequestPairFn ?? _defaultDeleteFriendRequestPair;

  /// Default implementation that invokes the Cloud Function.
  static Future<void> _defaultAcceptFriendRequest({
    required String fromUid,
    required String toUid,
    required String fromName,
    required String toName,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('acceptFriendRequest');
    await callable.call({
      'fromUid': fromUid,
      'toUid': toUid,
      'fromName': fromName,
      'toName': toName,
    });
  }

  /// Default implementation that invokes the Cloud Function to delete both
  /// friend request documents.
  static Future<void> _defaultDeleteFriendRequestPair({
    required String fromUid,
    required String toUid,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('deleteFriendRequestPair');
    await callable.call({
      'fromUid': fromUid,
      'toUid': toUid,
    });
  }

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

  /// Send a friend request from [fromUid] to the user with [toEmail].
  ///
  /// Looks up the UID associated with [toEmail] in the `users` collection and
  /// forwards to [sendFriendRequest]. Throws an [ArgumentError] if no user is
  /// found for the provided email address.
  Future<void> sendFriendRequestByEmail({
    required String fromUid,
    required String fromName,
    required String toEmail,
  }) async {
    final query = await firestore
        .collection(FriendCollections.users)
        .where('email', isEqualTo: toEmail)
        .limit(1)
        .get();
    if (query.docs.isEmpty) {
      throw ArgumentError('No user found with email $toEmail');
    }
    final toUid = query.docs.first.id;
    await sendFriendRequest(
      fromUid: fromUid,
      fromName: fromName,
      toUid: toUid,
    );
  }

  /// Accept a friend request sent by [fromUid] to [currentUid].
  Future<void> acceptFriendRequest({
    required String currentUid,
    required String fromUid,
    required String currentName,
    required String fromName,
  }) async {
    await _acceptFn(
      fromUid: fromUid,
      toUid: currentUid,
      fromName: fromName,
      toName: currentName,
    );

    // Delete the local received request if it still exists
    await firestore
        .collection(FriendCollections.users)
        .doc(currentUid)
        .collection(FriendCollections.receivedRequests)
        .doc(fromUid)
        .delete()
        .catchError((_) {});
  }

  /// Decline a friend request sent by [fromUid] to [currentUid].
  Future<void> declineFriendRequest({
    required String currentUid,
    required String fromUid,
  }) async {
    await _deleteFn(fromUid: fromUid, toUid: currentUid);

    // Delete the local received request if it still exists
    await firestore
        .collection(FriendCollections.users)
        .doc(currentUid)
        .collection(FriendCollections.receivedRequests)
        .doc(fromUid)
        .delete()
        .catchError((_) {});
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
