import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/achievement.dart';

/// Provides helper methods for unlocking and reading achievements.
class AchievementService {
  /// Firestore instance used for database operations.
  final FirebaseFirestore firestore;

  /// Creates an [AchievementService] using [FirebaseFirestore.instance] by default.
  AchievementService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  /// Path segment for the achievements collection under a user document.
  static const String achievementsCollection = 'achievements';

  /// Unlock an [achievement] for the user with [uid].
  Future<void> unlockAchievement(String uid, Achievement achievement) async {
    await firestore
        .collection('users')
        .doc(uid)
        .collection(achievementsCollection)
        .doc(achievement.id)
        .set({
      'title': achievement.title,
      'type': achievement.type,
      'dateUnlocked': Timestamp.fromDate(achievement.dateUnlocked),
    });
  }

  /// Stream of unlocked achievements for [uid].
  Stream<List<Achievement>> achievements(String uid) {
    return firestore
        .collection('users')
        .doc(uid)
        .collection(achievementsCollection)
        .orderBy('dateUnlocked', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return Achievement(
                id: doc.id,
                title: data['title'] ?? '',
                type: data['type'] ?? '',
                dateUnlocked: (data['dateUnlocked'] as Timestamp).toDate(),
              );
            }).toList());
  }

  /// Stream of ids for achievements unlocked by [uid].
  Stream<Set<String>> unlockedAchievementIds(String uid) {
    return firestore
        .collection('users')
        .doc(uid)
        .collection(achievementsCollection)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((d) => d.id).toSet());
  }
}
