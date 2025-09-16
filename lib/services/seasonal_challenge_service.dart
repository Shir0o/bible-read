import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/season.dart';
import '../models/seasonal_challenge.dart';
import '../models/seasonal_challenge_progress.dart';
import 'error_logger.dart';

/// Firestore paths used by the seasonal challenge feature.
class SeasonalChallengePaths {
  SeasonalChallengePaths._();

  /// Collection storing season definitions.
  static const String seasons = 'seasons';

  /// Sub-collection storing challenges under a season.
  static const String challenges = 'challenges';

  /// Sub-collection storing rewards under a season.
  static const String rewards = 'rewards';

  /// Top-level collection storing user documents.
  static const String users = 'users';

  /// Sub-collection storing per-user seasonal challenge progress.
  static const String userSeasonChallenges = 'seasonChallenges';
}

/// Provides helpers for reading seasonal challenges and updating progress.
class SeasonalChallengeService {
  /// Firestore instance used for reads and writes.
  final FirebaseFirestore firestore;

  final DateTime Function() _clock;

  /// Creates a [SeasonalChallengeService].
  SeasonalChallengeService({
    FirebaseFirestore? firestore,
    DateTime Function()? clock,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        _clock = clock ?? DateTime.now;

  /// Returns the currently active season, if any.
  Future<Season?> fetchActiveSeason() async {
    try {
      final snapshot =
          await firestore.collection(SeasonalChallengePaths.seasons).get();
      final now = _clock();
      Season? active;
      for (final doc in snapshot.docs) {
        final season = Season.fromFirestore(doc);
        if (season.isActive(now)) {
          if (active == null || season.startDate.isAfter(active.startDate)) {
            active = season;
          }
        }
      }
      return active;
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  /// Streams the list of challenges for [seasonId].
  Stream<List<SeasonalChallenge>> streamChallenges(String seasonId) {
    final query = firestore
        .collection(SeasonalChallengePaths.seasons)
        .doc(seasonId)
        .collection(SeasonalChallengePaths.challenges);
    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => SeasonalChallenge.fromFirestore(seasonId, doc))
          .toList();
    }).handleError((Object error, StackTrace stackTrace) {
      ErrorLogger.log(error, stackTrace);
    });
  }

  /// Streams a user's progress for [challengeId] within [seasonId].
  Stream<SeasonalChallengeProgress?> streamProgress({
    required String uid,
    required String seasonId,
    required String challengeId,
  }) {
    final doc = _progressDoc(uid, seasonId, challengeId);
    return doc.snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      return SeasonalChallengeProgress.fromFirestore(snapshot);
    }).handleError((Object error, StackTrace stackTrace) {
      ErrorLogger.log(error, stackTrace);
    });
  }

  /// Increments the daily progress for [challenge] by [amount].
  Future<SeasonalChallengeProgress> incrementDailyProgress({
    required String uid,
    required SeasonalChallenge challenge,
    int amount = 1,
  }) async {
    try {
      if (amount <= 0) {
        final existing =
            await _progressDoc(uid, challenge.seasonId, challenge.id).get();
        if (!existing.exists) {
          return SeasonalChallengeProgress(
            id: _progressId(challenge.seasonId, challenge.id),
            uid: uid,
            seasonId: challenge.seasonId,
            challengeId: challenge.id,
          );
        }
        return SeasonalChallengeProgress.fromFirestore(existing);
      }
      final now = _clock();
      final dayKey = _formatDay(now);
      final docRef = _progressDoc(uid, challenge.seasonId, challenge.id);
      return firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        SeasonalChallengeProgress progress;
        if (snapshot.exists) {
          progress = SeasonalChallengeProgress.fromFirestore(snapshot);
        } else {
          progress = SeasonalChallengeProgress(
            id: docRef.id,
            uid: uid,
            seasonId: challenge.seasonId,
            challengeId: challenge.id,
          );
        }

        final appliedAmount = _appliedIncrement(
          current: progress.totalProgress,
          goal: challenge.goal,
          amount: amount,
        );
        final updatedMap = Map<String, int>.from(progress.dailyProgress);
        updatedMap[dayKey] = (updatedMap[dayKey] ?? 0) + appliedAmount;
        final newTotal = progress.totalProgress + appliedAmount;
        final completedAt = progress.completedAt ??
            (challenge.goal > 0 && newTotal >= challenge.goal ? now : null);

        final updatedProgress = SeasonalChallengeProgress(
          id: progress.id,
          uid: progress.uid.isEmpty ? uid : progress.uid,
          seasonId: progress.seasonId.isEmpty
              ? challenge.seasonId
              : progress.seasonId,
          challengeId: progress.challengeId.isEmpty
              ? challenge.id
              : progress.challengeId,
          dailyProgress: updatedMap,
          totalProgress: newTotal,
          updatedAt: now,
          completedAt: completedAt,
          rewardClaimedAt: progress.rewardClaimedAt,
        );

        transaction.set(docRef, updatedProgress.toFirestore());
        return updatedProgress;
      });
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  /// Marks the reward for [progress] as claimed for [uid].
  Future<SeasonalChallengeProgress> claimReward({
    required String uid,
    required SeasonalChallengeProgress progress,
  }) async {
    try {
      final docRef = _progressDoc(uid, progress.seasonId, progress.challengeId);
      final claimedAt = _clock();
      final updated = SeasonalChallengeProgress(
        id: progress.id.isEmpty ? docRef.id : progress.id,
        uid: progress.uid.isEmpty ? uid : progress.uid,
        seasonId: progress.seasonId,
        challengeId: progress.challengeId,
        dailyProgress: progress.dailyProgress,
        totalProgress: progress.totalProgress,
        updatedAt: claimedAt,
        completedAt: progress.completedAt,
        rewardClaimedAt: claimedAt,
      );
      await docRef.set(updated.toFirestore(), SetOptions(merge: true));
      return updated;
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  DocumentReference<Map<String, dynamic>> _progressDoc(
    String uid,
    String seasonId,
    String challengeId,
  ) {
    return firestore
        .collection(SeasonalChallengePaths.users)
        .doc(uid)
        .collection(SeasonalChallengePaths.userSeasonChallenges)
        .doc(_progressId(seasonId, challengeId));
  }

  String _progressId(String seasonId, String challengeId) =>
      '${seasonId}_$challengeId';

  static int _appliedIncrement({
    required int current,
    required int goal,
    required int amount,
  }) {
    if (goal <= 0) {
      return amount;
    }
    final remaining = goal - current;
    if (remaining <= 0) {
      return 0;
    }
    return amount > remaining ? remaining : amount;
  }

  static String _formatDay(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
