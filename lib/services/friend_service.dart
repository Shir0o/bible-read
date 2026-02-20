import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'error_logger.dart';
import '../models/app_notification.dart';
import '../models/notification_preferences.dart';
import 'notification_service.dart';

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

  /// Sub-collection recording nudge history.
  static const String nudges = 'nudges';
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

/// Signature for calling the `sendNudgeNotification` Cloud Function.
typedef SendNudgeNotificationFn = Future<NudgeResult> Function({
  required String fromUid,
  required String toUid,
  required String fromName,
});

/// Possible outcomes when sending a nudge.
enum NudgeResult {
  /// The nudge was sent successfully.
  sent,

  /// A nudge was already sent today.
  alreadySent,

  /// The friend already read today.
  alreadyRead,
}

/// Provides helper methods for friend request CRUD operations.
class FriendService {
  /// Firestore instance used for database operations.
  final FirebaseFirestore firestore;

  /// Service for writing notification documents.
  final NotificationService notificationService;

  /// Function used to invoke the accept friend request Cloud Function.
  final AcceptFriendRequestFn _acceptFn;

  /// Function used to invoke the delete friend request pair Cloud Function.
  final DeleteFriendRequestPairFn _deleteFn;

  /// Function used to invoke the send nudge notification Cloud Function.
  final SendNudgeNotificationFn _nudgeFn;

  /// Creates a [FriendService] using [FirebaseFirestore.instance] by default.
  FriendService({
    FirebaseFirestore? firestore,
    NotificationService? notificationService,
    AcceptFriendRequestFn? acceptFriendRequestFn,
    DeleteFriendRequestPairFn? deleteFriendRequestPairFn,
    SendNudgeNotificationFn? sendNudgeNotificationFn,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        notificationService = notificationService ??
            NotificationService(
                firestore: firestore ?? FirebaseFirestore.instance),
        _acceptFn = acceptFriendRequestFn ?? _defaultAcceptFriendRequest,
        _deleteFn =
            deleteFriendRequestPairFn ?? _defaultDeleteFriendRequestPair,
        _nudgeFn = sendNudgeNotificationFn ?? _defaultSendNudgeNotification;

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

  /// Default implementation that invokes the Cloud Function to send a nudge.
  static Future<NudgeResult> _defaultSendNudgeNotification({
    required String fromUid,
    required String toUid,
    required String fromName,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('sendNudgeNotification');
    final result = await callable.call<Map<String, dynamic>>({
      'toUid': toUid,
      'fromName': fromName,
    });
    final data = result.data;
    if (data['alreadyRead'] == true) {
      return NudgeResult.alreadyRead;
    }
    if (data['alreadySent'] == true) {
      return NudgeResult.alreadySent;
    }
    return NudgeResult.sent;
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

    // Use a deterministic ID to avoid duplicate notifications per sender.
    final deterministicId = 'friendRequest_$fromUid';
    final notification = AppNotification(
      id: deterministicId,
      type: NotificationType.friendRequest,
      fromUid: fromUid,
      senderUid: fromUid,
      message:
          fromName.isNotEmpty ? '$fromName sent you a friend request' : null,
      timestamp: DateTime.now(),
      read: false,
    );
    // Merge to update timestamp/message and reset read=false while keeping a single doc.
    await firestore
        .collection(NotificationCollections.users)
        .doc(toUid)
        .collection(NotificationCollections.notifications)
        .doc(deterministicId)
        .set(notification.toFirestore(), SetOptions(merge: true));
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
        .where('email', isEqualTo: toEmail.toLowerCase())
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
        .catchError((e, st) {
      if (kDebugMode) {
        debugPrint('Failed to remove received request for $fromUid: $e');
      }
      ErrorLogger.log(e, st);
    });

    try {
      final snap = await firestore
          .collection(NotificationCollections.users)
          .doc(currentUid)
          .collection(NotificationCollections.notifications)
          .where('type', isEqualTo: NotificationType.friendRequest.name)
          .where('fromUid', isEqualTo: fromUid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        await snap.docs.first.reference
            .set({'read': true}, SetOptions(merge: true));
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to mark friend request notification as read: $e');
      }
      ErrorLogger.log(e, st);
    }
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
        .catchError((e, st) {
      if (kDebugMode) {
        debugPrint('Failed to remove received request for $fromUid: $e');
      }
      ErrorLogger.log(e, st);
    });

    try {
      final snap = await firestore
          .collection(NotificationCollections.users)
          .doc(currentUid)
          .collection(NotificationCollections.notifications)
          .where('type', isEqualTo: NotificationType.friendRequest.name)
          .where('fromUid', isEqualTo: fromUid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        await snap.docs.first.reference.delete();
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to remove friend request notification: $e');
      }
      ErrorLogger.log(e, st);
    }
  }

  /// Send a nudge notification to [friendUid] from [currentUid].
  Future<NudgeResult> nudgeFriend({
    required String currentUid,
    required String friendUid,
    required String currentName,
  }) async {
    return _nudgeFn(
      fromUid: currentUid,
      toUid: friendUid,
      fromName: currentName,
    );
  }

  /// Stream of friend UIDs nudged today by [uid].
  Stream<Set<String>> nudgedToday(String uid) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return firestore
        .collection(FriendCollections.users)
        .doc(uid)
        .collection(FriendCollections.nudges)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toSet());
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
