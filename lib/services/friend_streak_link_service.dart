import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/friend_streak_link.dart';
import 'error_logger.dart';
import 'friend_service.dart';

/// Propagates read coverage events to paired friend streak links.
class FriendStreakLinkService {
  FriendStreakLinkService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  /// Firestore instance used for streak link updates.
  final FirebaseFirestore firestore;

  /// Records the latest coverage date for [uid] across every accepted link.
  ///
  /// The method skips updates when [coveredDate] is `null` or when the streak
  /// advancement was satisfied purely via grace credits.
  Future<void> recordCoverage(
    String uid,
    DateTime? coveredDate,
    bool coveredViaGrace,
  ) async {
    if (uid.isEmpty || coveredDate == null || coveredViaGrace) {
      return;
    }

    final normalized = _dateOnly(coveredDate);

    try {
      final linksSnapshot = await _linksRef(uid)
          .where('status', isEqualTo: FriendStreakStatus.active.name)
          .get();
      if (linksSnapshot.docs.isEmpty) {
        return;
      }

      for (final doc in linksSnapshot.docs) {
        final partnerUid = doc.id;
        final ownerRef = doc.reference;
        final partnerRef = _linksRef(partnerUid).doc(uid);

        await firestore.runTransaction((transaction) async {
          final ownerSnap = await transaction.get(ownerRef);
          final partnerSnap = await transaction.get(partnerRef);
          if (!ownerSnap.exists) {
            return;
          }

          final data = ownerSnap.data() ?? const <String, dynamic>{};
          final lastUser = _parseDate(data['lastUserCovered']);
          if (lastUser != null && _isSameDay(lastUser, normalized)) {
            return;
          }

          final lastPartner = _parseDate(data['lastPartnerCovered']);
          final currentStreak = (data['currentStreak'] as num?)?.toInt() ?? 0;
          final partnerMatches =
              lastPartner != null && _isSameDay(lastPartner, normalized);

          final updates = <String, dynamic>{
            'lastUserCovered': Timestamp.fromDate(normalized),
            'currentStreak': partnerMatches ? currentStreak + 1 : 1,
            'updatedAt': Timestamp.now(),
            'streakBrokenOn': partnerMatches
                ? FieldValue.delete()
                : Timestamp.fromDate(normalized),
          };
          transaction.update(ownerRef, updates);

          if (!partnerSnap.exists) {
            return;
          }

          final partnerUpdates = <String, dynamic>{
            'lastPartnerCovered': Timestamp.fromDate(normalized),
            'updatedAt': Timestamp.now(),
          };
          if (partnerMatches) {
            partnerUpdates['currentStreak'] = currentStreak + 1;
            partnerUpdates['streakBrokenOn'] = FieldValue.delete();
          }
          transaction.update(partnerRef, partnerUpdates);
        });
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  CollectionReference<Map<String, dynamic>> _linksRef(String uid) {
    return firestore
        .collection(FriendCollections.users)
        .doc(uid)
        .collection(FriendCollections.friendStreakLinks);
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime? _parseDate(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return null;
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
