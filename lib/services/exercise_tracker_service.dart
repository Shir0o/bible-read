import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/exercise_challenge.dart';
import '../models/exercise_progress.dart';
import 'error_logger.dart';

/// Convenience helpers for locating exercise challenge collections.
class ExerciseTrackerPaths {
  ExerciseTrackerPaths._();

  /// Top-level Firestore collection storing user documents.
  static const String users = 'users';

  /// Sub-collection storing user defined exercise challenges.
  static const String challenges = 'exerciseChallenges';

  /// Sub-collection storing per-day exercise progress documents.
  static const String progress = 'exerciseProgress';
}

/// Summary information returned for an exercise challenge.
class ExerciseChallengeSummary {
  /// Challenge definition.
  final ExerciseChallenge challenge;

  /// Total recorded for today.
  final double todayTotal;

  /// Whether today's total meets the configured goal.
  final bool goalMetToday;

  /// Consecutive days with the goal met up to today.
  final int currentStreak;

  /// Total number of days the goal has been met.
  final int completedDays;

  /// Aggregated total amount recorded across all time.
  final double totalRecorded;

  /// Recent totals keyed by `yyyy-MM-dd` for UI graphs.
  final Map<String, double> recentTotals;

  /// Creates an [ExerciseChallengeSummary].
  const ExerciseChallengeSummary({
    required this.challenge,
    required this.todayTotal,
    required this.goalMetToday,
    required this.currentStreak,
    required this.completedDays,
    required this.totalRecorded,
    required this.recentTotals,
  });
}

/// Provides helpers for managing custom exercise challenges and progress.
class ExerciseTrackerService {
  /// Firestore instance used for reads and writes.
  final FirebaseFirestore firestore;

  /// Authentication instance for the current user.
  final FirebaseAuth auth;

  final DateTime Function() _clock;

  /// Creates an [ExerciseTrackerService].
  ExerciseTrackerService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    DateTime Function()? clock,
  }) : firestore = firestore ?? FirebaseFirestore.instance,
       auth = auth ?? FirebaseAuth.instance,
       _clock = clock ?? DateTime.now;

  /// Streams active challenge definitions for the current user.
  Stream<List<ExerciseChallenge>> streamActiveChallenges({String? uid}) async* {
    final collection = await _resolveChallengesCollection(uid);
    yield* collection
        .where('archived', isEqualTo: false)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(ExerciseChallenge.fromFirestore).toList(),
        )
        .handleError((Object error, StackTrace stackTrace) {
          ErrorLogger.log(error, stackTrace);
        });
  }

  /// Fetches the active challenge definitions for the user.
  Future<List<ExerciseChallenge>> fetchActiveChallenges({String? uid}) async {
    try {
      final collection = await _resolveChallengesCollection(uid);
      final snapshot = await collection
          .where('archived', isEqualTo: false)
          .get();
      return snapshot.docs.map(ExerciseChallenge.fromFirestore).toList();
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  /// Creates or updates a challenge definition.
  Future<ExerciseChallenge> upsertChallenge(ExerciseChallenge challenge) async {
    try {
      final resolvedUid = await _resolveUid(
        challenge.uid.isEmpty ? null : challenge.uid,
      );
      final collection = firestore
          .collection(ExerciseTrackerPaths.users)
          .doc(resolvedUid)
          .collection(ExerciseTrackerPaths.challenges);
      final now = _clock();
      final docRef = challenge.id.isEmpty
          ? collection.doc()
          : collection.doc(challenge.id);
      final updatedChallenge = ExerciseChallenge(
        id: docRef.id,
        uid: resolvedUid,
        name: challenge.name,
        unit: challenge.unit,
        dailyGoal: challenge.dailyGoal,
        targetType: challenge.targetType,
        totalTarget: challenge.totalTarget,
        categories: challenge.categories,
        archived: challenge.archived,
        createdAt: challenge.createdAt ?? now,
        updatedAt: now,
      );
      await docRef.set(updatedChallenge.toFirestore());
      return updatedChallenge;
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  /// Records [amount] of progress for [challenge] on [date].
  ///
  /// When [replace] is true the amount overwrites the stored value instead of
  /// incrementing it. Progress entries that reach zero are removed.
  Future<ExerciseProgress> recordDailyAmount({
    required ExerciseChallenge challenge,
    required double amount,
    DateTime? date,
    bool replace = false,
    String? uid,
  }) async {
    try {
      if (amount == 0 && !replace) {
        final resolvedUid = await _resolveUid(uid ?? challenge.uid);
        final day = _normalizeDate(date ?? _clock());
        final docRef = _progressCollection(resolvedUid).doc(_formatDay(day));
        final snapshot = await docRef.get();
        if (!snapshot.exists) {
          return ExerciseProgress(id: docRef.id, uid: resolvedUid, date: day);
        }
        return ExerciseProgress.fromFirestore(snapshot);
      }

      if (amount < 0 && !replace) {
        throw ArgumentError.value(amount, 'amount', 'must be positive');
      }

      final resolvedUid = await _resolveUid(uid ?? challenge.uid);
      final day = _normalizeDate(date ?? _clock());
      final docRef = _progressCollection(resolvedUid).doc(_formatDay(day));

      return firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        ExerciseProgress progress;
        if (snapshot.exists) {
          progress = ExerciseProgress.fromFirestore(snapshot);
        } else {
          progress = ExerciseProgress(
            id: docRef.id,
            uid: resolvedUid,
            date: day,
          );
        }

        final totals = Map<String, double>.from(progress.totals);
        if (replace) {
          if (amount <= 0) {
            totals.remove(challenge.id);
          } else {
            totals[challenge.id] = amount;
          }
        } else {
          final next = (totals[challenge.id] ?? 0) + amount;
          if (next <= 0) {
            totals.remove(challenge.id);
          } else {
            totals[challenge.id] = next;
          }
        }

        final updatedProgress = ExerciseProgress(
          id: progress.id,
          uid: resolvedUid,
          date: day,
          totals: totals,
          updatedAt: _clock(),
        );

        transaction.set(docRef, updatedProgress.toFirestore());
        return updatedProgress;
      });
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to record exercise amount: $e');
      }
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  /// Returns summary data for each active challenge.
  Future<List<ExerciseChallengeSummary>> fetchChallengeSummaries({
    String? uid,
    int recentDays = 30,
  }) async {
    assert(recentDays > 0, 'recentDays must be positive');
    try {
      final resolvedUid = await _resolveUid(uid);
      final challenges = await fetchActiveChallenges(uid: resolvedUid);
      if (challenges.isEmpty) {
        return const <ExerciseChallengeSummary>[];
      }

      final progressSnapshot = await _progressCollection(resolvedUid).get();
      final progressByDay = <String, ExerciseProgress>{};
      for (final doc in progressSnapshot.docs) {
        final progress = ExerciseProgress.fromFirestore(doc);
        progressByDay[doc.id] = progress;
      }

      final challengeById = {for (final c in challenges) c.id: c};
      final totalsByChallenge = <String, double>{};
      final completionsByChallenge = <String, Map<String, bool>>{};

      for (final entry in progressByDay.entries) {
        final dayKey = entry.key;
        final totals = entry.value.totals;
        totals.forEach((challengeId, amount) {
          totalsByChallenge[challengeId] =
              (totalsByChallenge[challengeId] ?? 0) + amount;
          final challenge = challengeById[challengeId];
          if (challenge == null) {
            return;
          }
          final completions = completionsByChallenge.putIfAbsent(
            challengeId,
            () => <String, bool>{},
          );
          completions[dayKey] = _meetsGoal(challenge, amount);
        });
      }

      final today = _normalizeDate(_clock());
      final todayKey = _formatDay(today);
      final startRecent = today.subtract(Duration(days: recentDays - 1));

      return challenges
          .map((challenge) {
            final completions = completionsByChallenge[challenge.id] ?? {};
            final streak = _calculateStreak(
              completions: completions,
              today: today,
            );
            final todayTotal =
                progressByDay[todayKey]?.totalForChallenge(challenge.id) ?? 0;
            final goalMetToday =
                completions[todayKey] ?? _meetsGoal(challenge, todayTotal);

            final recentTotals = <String, double>{};
            for (int i = 0; i < recentDays; i++) {
              final date = startRecent.add(Duration(days: i));
              final key = _formatDay(date);
              final total =
                  progressByDay[key]?.totalForChallenge(challenge.id) ?? 0;
              if (total > 0) {
                recentTotals[key] = total;
              }
            }

            final completedDays = completions.values.where((met) => met).length;

            return ExerciseChallengeSummary(
              challenge: challenge,
              todayTotal: todayTotal,
              goalMetToday: goalMetToday,
              currentStreak: streak,
              completedDays: completedDays,
              totalRecorded: totalsByChallenge[challenge.id] ?? 0,
              recentTotals: Map.unmodifiable(recentTotals),
            );
          })
          .toList(growable: false);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to load exercise challenge summaries: $e');
      }
      await ErrorLogger.log(e, st);
      rethrow;
    }
  }

  Future<CollectionReference<Map<String, dynamic>>>
  _resolveChallengesCollection(String? uid) async {
    final resolvedUid = await _resolveUid(uid);
    return firestore
        .collection(ExerciseTrackerPaths.users)
        .doc(resolvedUid)
        .collection(ExerciseTrackerPaths.challenges);
  }

  CollectionReference<Map<String, dynamic>> _progressCollection(String uid) {
    return firestore
        .collection(ExerciseTrackerPaths.users)
        .doc(uid)
        .collection(ExerciseTrackerPaths.progress);
  }

  Future<String> _resolveUid(String? uid) async {
    if (uid != null && uid.isNotEmpty) {
      return uid;
    }
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user available.');
    }
    return user.uid;
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _formatDay(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  bool _meetsGoal(ExerciseChallenge challenge, double amount) {
    switch (challenge.targetType) {
      case ExerciseTargetType.atLeast:
        if (challenge.dailyGoal <= 0) {
          return amount >= 0;
        }
        return amount >= challenge.dailyGoal;
      case ExerciseTargetType.atMost:
        if (challenge.dailyGoal <= 0) {
          return amount <= 0;
        }
        return amount <= challenge.dailyGoal;
      case ExerciseTargetType.exactly:
        if (challenge.dailyGoal <= 0) {
          return amount.abs() < 0.0001;
        }
        return (amount - challenge.dailyGoal).abs() < 0.0001;
    }
  }

  int _calculateStreak({
    required Map<String, bool> completions,
    required DateTime today,
  }) {
    DateTime? latestRecordedDay;
    final normalizedToday = _normalizeDate(today);

    for (final entry in completions.entries) {
      final parsed = DateTime.tryParse(entry.key);
      if (parsed == null) {
        continue;
      }
      final normalized = _normalizeDate(parsed);
      if (normalized.isAfter(normalizedToday)) {
        continue;
      }
      if (latestRecordedDay == null || normalized.isAfter(latestRecordedDay)) {
        latestRecordedDay = normalized;
      }
    }

    if (latestRecordedDay == null) {
      return 0;
    }

    if (normalizedToday.difference(latestRecordedDay).inDays > 1) {
      return 0;
    }

    int streak = 0;
    var cursor = latestRecordedDay;
    while (true) {
      final dateKey = _formatDay(cursor);
      final metGoal = completions[dateKey] ?? false;
      if (!metGoal) {
        break;
      }

      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }
}
