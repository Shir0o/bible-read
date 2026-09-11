import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

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

  /// The member already read today.
  alreadyRead,
}

/// Sends nudges — gentle prompts one reader sends another in their Circle —
/// and streams the per-day nudge ledger. Person-to-person: any co-member can
/// be nudged, friendship not required.
class NudgeService {
  /// Firestore instance used for database operations.
  final FirebaseFirestore firestore;

  /// Function used to invoke the send nudge notification Cloud Function.
  final SendNudgeNotificationFn _nudgeFn;

  /// Creates a [NudgeService] using [FirebaseFirestore.instance] by default.
  NudgeService({
    FirebaseFirestore? firestore,
    SendNudgeNotificationFn? sendNudgeNotificationFn,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        _nudgeFn = sendNudgeNotificationFn ?? _defaultSendNudgeNotification;

  /// Default implementation that invokes the Cloud Function to send a nudge.
  static Future<NudgeResult> _defaultSendNudgeNotification({
    required String fromUid,
    required String toUid,
    required String fromName,
  }) async {
    final callable = FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('sendNudgeNotification');
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

  /// Send a nudge notification to a fellow Circle member. A Nudge is
  /// person-to-person: any co-member can be nudged, friendship not required.
  Future<NudgeResult> nudgeMember({
    required String currentUid,
    required String memberUid,
    required String currentName,
  }) async {
    return _nudgeFn(
      fromUid: currentUid,
      toUid: memberUid,
      fromName: currentName,
    );
  }

  /// Stream of Circle member UIDs nudged today by [uid].
  Stream<Set<String>> nudgedToday(String uid) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return firestore
        .collection('users')
        .doc(uid)
        .collection('nudges')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toSet());
  }
}
