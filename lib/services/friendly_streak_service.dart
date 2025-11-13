import 'package:cloud_firestore/cloud_firestore.dart';

import 'error_logger.dart';

/// Loads friendly streak metrics derived from the user's friends list.
class FriendlyStreakService {
  /// Firestore instance used to read friend summaries.
  final FirebaseFirestore firestore;

  FriendlyStreakService({FirebaseFirestore? firestore})
    : firestore = firestore ?? FirebaseFirestore.instance;

  /// Returns the highest streak length among the user's approved friends.
  ///
  /// Returns `null` when the user has no friends with streak data or when the
  /// query fails.
  Future<int?> fetchTopStreak(String uid) async {
    try {
      final friendsSnapshot = await firestore
          .collection('users')
          .doc(uid)
          .collection('friends')
          .get();
      final friendIds = friendsSnapshot.docs
          .where((doc) => doc.id != 'init')
          .map((doc) => doc.id)
          .toList();
      if (friendIds.isEmpty) return null;

      final summaryFutures = friendIds.map(
        (friendId) => firestore
            .collection('users')
            .doc(friendId)
            .collection('summary')
            .doc('data')
            .get(),
      );
      final summaries = await Future.wait(summaryFutures);

      int? topStreak;
      for (final summary in summaries) {
        final data = summary.data();
        if (data == null) continue;
        final raw = data['streak'];
        final streak = raw is int
            ? raw
            : raw is num
            ? raw.toInt()
            : null;
        if (streak == null) continue;
        if (topStreak == null || streak > topStreak) {
          topStreak = streak;
        }
      }
      return topStreak;
    } catch (e, st) {
      ErrorLogger.log(e, st);
      return null;
    }
  }
}
