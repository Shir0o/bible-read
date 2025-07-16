import 'package:cloud_firestore/cloud_firestore.dart';

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
    final now = Timestamp.now();
    await Future.wait([
      firestore
          .collection('users')
          .doc(fromUid)
          .collection('friendRequestsSent')
          .doc(toUid)
          .set({'timestamp': now}),
      firestore
          .collection('users')
          .doc(toUid)
          .collection('friendRequestsReceived')
          .doc(fromUid)
          .set({'timestamp': now, 'name': fromName}),
    ]);
  }

  /// Accept a friend request sent by [fromUid] to [currentUid].
  Future<void> acceptFriendRequest({
    required String currentUid,
    required String fromUid,
  }) async {
    final fromRef = firestore.collection('users').doc(fromUid);
    final toRef = firestore.collection('users').doc(currentUid);

    final fromData = await fromRef.get();
    final toData = await toRef.get();
    final fromName = fromData.data()?['name'] ?? '';
    final toName = toData.data()?['name'] ?? '';

    await Future.wait([
      fromRef.collection('friendRequestsSent').doc(currentUid).delete(),
      toRef.collection('friendRequestsReceived').doc(fromUid).delete(),
      fromRef
          .collection('friends')
          .doc(currentUid)
          .set({'timestamp': Timestamp.now(), 'name': toName}),
      toRef
          .collection('friends')
          .doc(fromUid)
          .set({'timestamp': Timestamp.now(), 'name': fromName}),
    ]);
  }

  /// Decline a friend request sent by [fromUid] to [currentUid].
  Future<void> declineFriendRequest({
    required String currentUid,
    required String fromUid,
  }) async {
    await Future.wait([
      firestore
          .collection('users')
          .doc(fromUid)
          .collection('friendRequestsSent')
          .doc(currentUid)
          .delete(),
      firestore
          .collection('users')
          .doc(currentUid)
          .collection('friendRequestsReceived')
          .doc(fromUid)
          .delete(),
    ]);
  }

  /// Stream of pending friend requests for [uid].
  Stream<List<Map<String, dynamic>>> pendingRequests(String uid) {
    return firestore
        .collection('users')
        .doc(uid)
        .collection('friendRequestsReceived')
        .snapshots()
        .map((s) => s.docs
            .where((d) => d.id != 'init')
            .map((d) => {'uid': d.id, ...d.data()})
            .toList());
  }

  /// Stream of friends for [uid].
  Stream<List<Map<String, dynamic>>> friends(String uid) {
    return firestore
        .collection('users')
        .doc(uid)
        .collection('friends')
        .snapshots()
        .map((s) => s.docs
            .where((d) => d.id != 'init')
            .map((d) => {'uid': d.id, ...d.data()})
            .toList());
  }
}
