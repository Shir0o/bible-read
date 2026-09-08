import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';

class ReadingPlanService {
  final FirebaseFirestore firestore;

  ReadingPlanService({required this.firestore});

  /// Loads available reading plans from local assets and Firestore.
  Future<List<ReadingPlan>> getAvailablePlans({String? userId}) async {
    List<ReadingPlan> allPlans = [];

    // No longer loading asset-based plans as per user request

    // Load custom plans from Firestore
    if (userId != null) {
      try {
        final snapshot = await firestore
            .collection('custom_plans')
            .where('userId', isEqualTo: userId)
            .get();
        final customPlans = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return ReadingPlan.fromJson(data);
        }).toList();
        allPlans.addAll(customPlans);
      } catch (e) {
        if (kDebugMode) {
          print('Error loading custom reading plans: $e');
        }
      }
    }

    return allPlans;
  }

  /// Gets a specific plan by ID.
  Future<ReadingPlan?> getPlanById(String planId, {String? userId}) async {
    final plans = await getAvailablePlans(userId: userId);
    try {
      return plans.firstWhere((p) => p.id == planId);
    } catch (e) {
      // Try fetching directly from Firestore if not in cache
      try {
        final doc =
            await firestore.collection('custom_plans').doc(planId).get();
        if (doc.exists) {
          final data = doc.data()!;
          data['id'] = doc.id;
          return ReadingPlan.fromJson(data);
        }
      } catch (_) {}
      return null;
    }
  }

  /// Saves a custom reading plan to Firestore.
  Future<String> saveCustomPlan(String userId, ReadingPlan plan) async {
    final data = plan.toJson();
    data['userId'] = userId;
    data['createdAt'] = FieldValue.serverTimestamp();

    final docRef = await firestore.collection('custom_plans').add(data);
    return docRef.id;
  }

  /// Updates an existing custom reading plan in place, preserving its document
  /// id (and, via merge, its `userId`/`createdAt`). Used by the edit flow so a
  /// plan's progress — tracked separately under `plan_progress/{planId}` —
  /// survives the edit.
  Future<void> updateCustomPlan(String userId, ReadingPlan plan) async {
    final data = plan.toJson();
    data['userId'] = userId;
    data['updatedAt'] = FieldValue.serverTimestamp();

    await firestore
        .collection('custom_plans')
        .doc(plan.id)
        .set(data, SetOptions(merge: true));
  }

  /// Starts a reading plan for a user.
  ///
  /// Returns the soft-deleted progress record when the same plan was moved to
  /// the Recently Deleted hub and never restored or purged (#776) — the
  /// caller offers restore-progress vs start-fresh and calls again with
  /// [restoreDeleted] to keep the old record. Null means a fresh start
  /// happened (or the plan was simply started).
  Future<UserPlanProgress?> startPlan(
    String userId,
    String planId, {
    DateTime? startDate,
    bool restoreDeleted = false,
  }) async {
    final docRef = firestore
        .collection('users')
        .doc(userId)
        .collection('plan_progress')
        .doc(planId);
    final existing = await docRef.get();

    // Re-enrollment collision (#776): a soft-deleted record still exists.
    if (existing.exists) {
      final previous = UserPlanProgress.fromFirestore(existing);
      if (previous.deletedAt != null) {
        if (!restoreDeleted) return previous;
        // Restore the prior record intact — its start date and completed
        // days come back, nothing is reset.
        await docRef.update({
          'deletedAt': null,
          'deleteAfter': null,
          'preDeleteState': null,
        });
        return null;
      }
    }

    final progress = UserPlanProgress(
      planId: planId,
      userId: userId,
      startDate: startDate ?? DateTime.now(),
      completedDays: [],
    );

    await docRef.set(progress.toFirestore());
    return null;
  }

  /// Removes a reading plan for a user.
  Future<void> leavePlan(String userId, String planId) async {
    await firestore
        .collection('users')
        .doc(userId)
        .collection('plan_progress')
        .doc(planId)
        .delete();
  }

  /// Moves a plan to the Recently Deleted hub (#776): the progress document
  /// keeps its id and history but gains a 30-day purge deadline. [preDeleteState]
  /// records whether it was archived, so restoring puts it back exactly.
  Future<void> softDeletePlan(
    String userId,
    String planId, {
    DateTime? now,
  }) async {
    final docRef = firestore
        .collection('users')
        .doc(userId)
        .collection('plan_progress')
        .doc(planId);
    final snap = await docRef.get();
    if (!snap.exists) return;
    final progress = UserPlanProgress.fromFirestore(snap);
    final deletedAt = now ?? DateTime.now();
    await docRef.update({
      'deletedAt': Timestamp.fromDate(deletedAt),
      'deleteAfter':
          Timestamp.fromDate(deletedAt.add(const Duration(days: 30))),
      'preDeleteState': progress.isArchived ? 'archived' : 'active',
    });
  }

  /// Returns a soft-deleted plan to its pre-deletion state (#776): archived
  /// plans return to the Archive hub, active ones to the active lists.
  Future<void> restorePlan(String userId, String planId) async {
    final docRef = firestore
        .collection('users')
        .doc(userId)
        .collection('plan_progress')
        .doc(planId);
    final snap = await docRef.get();
    if (!snap.exists) return;
    final progress = UserPlanProgress.fromFirestore(snap);
    final wasArchived = progress.preDeleteState == 'archived';
    await docRef.update({
      'isArchived': wasArchived,
      'deletedAt': null,
      'deleteAfter': null,
      'preDeleteState': null,
    });
  }

  /// Permanently purges a soft-deleted plan's progress document.
  Future<void> permanentlyDeletePlan(String userId, String planId) =>
      leavePlan(userId, planId);

  /// Streams the user's progress for a specific plan.
  Stream<UserPlanProgress?> getPlanProgress(String userId, String planId) {
    return firestore
        .collection('users')
        .doc(userId)
        .collection('plan_progress')
        .doc(planId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return UserPlanProgress.fromFirestore(doc);
    });
  }

  /// Streams all active (non-archived, not soft-deleted) plans for a user.
  Stream<List<UserPlanProgress>> getActivePlans(String userId) {
    return firestore
        .collection('users')
        .doc(userId)
        .collection('plan_progress')
        .where('isArchived', isEqualTo: false)
        .where('deletedAt', isNull: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => UserPlanProgress.fromFirestore(doc))
          .toList();
    });
  }

  /// Streams all archived plans for a user (soft-deleted ones excluded —
  /// they live in the Recently Deleted hub until restored or purged).
  Stream<List<UserPlanProgress>> getArchivedPlans(String userId) {
    return firestore
        .collection('users')
        .doc(userId)
        .collection('plan_progress')
        .where('isArchived', isEqualTo: true)
        .where('deletedAt', isNull: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => UserPlanProgress.fromFirestore(doc))
          .toList();
    });
  }

  /// Streams everything sitting in the Recently Deleted hub (#776).
  Stream<List<UserPlanProgress>> getDeletedPlans(String userId) {
    return firestore
        .collection('users')
        .doc(userId)
        .collection('plan_progress')
        .where('deletedAt', isNull: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => UserPlanProgress.fromFirestore(doc))
          .toList();
    });
  }

  /// Sets the archived status of a plan.
  Future<void> setPlanArchived(
    String userId,
    String planId,
    bool isArchived,
  ) async {
    final docRef = firestore
        .collection('users')
        .doc(userId)
        .collection('plan_progress')
        .doc(planId);
    await docRef.update({
      'isArchived': isArchived,
      'archivedAt': isArchived ? Timestamp.now() : null,
    });
  }

  /// Archives a plan (#776): it leaves the active lists but keeps its
  /// progress and shows in the Archive hub.
  Future<void> archivePlan(String userId, String planId) =>
      setPlanArchived(userId, planId, true);

  /// Unarchives a plan — it returns to the active lists with all progress.
  Future<void> unarchivePlan(String userId, String planId) =>
      setPlanArchived(userId, planId, false);

  /// Marks a specific day in the plan as completed.
  Future<void> markDayComplete(String userId, String planId, int day) async {
    final docRef = firestore
        .collection('users')
        .doc(userId)
        .collection('plan_progress')
        .doc(planId);

    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;

      final progress = UserPlanProgress.fromFirestore(snapshot);
      if (!progress.completedDays.contains(day)) {
        final updatedCompletedDays = List<int>.from(progress.completedDays)
          ..add(day)
          ..sort(); // Keep sorted

        transaction.update(docRef, {
          'completedDays': updatedCompletedDays,
          'lastReadDate': Timestamp.now(),
        });
      }
    });
  }

  /// Unmarks a specific day in the plan.
  Future<void> unmarkDayComplete(String userId, String planId, int day) async {
    final docRef = firestore
        .collection('users')
        .doc(userId)
        .collection('plan_progress')
        .doc(planId);

    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;

      final progress = UserPlanProgress.fromFirestore(snapshot);
      if (progress.completedDays.contains(day)) {
        final updatedCompletedDays = List<int>.from(progress.completedDays)
          ..remove(day);

        transaction.update(docRef, {
          'completedDays': updatedCompletedDays,
          // We don't necessarily revert lastReadDate easily without history,
          // so we leave it or typically you'd check if it was today.
          // For simplicity, we leave it.
        });
      }
    });
  }

  /// Returns the readings for the user's "next" due day.
  /// This is a helper to find the first incomplete day.
  /// Returns null if plan is completed.
  ReadingPlanDay? getNextDueDay(ReadingPlan plan, UserPlanProgress progress) {
    for (final day in plan.schedule) {
      if (!progress.completedDays.contains(day.day)) {
        return day;
      }
    }
    return null; // All done!
  }

  /// Calculates the scheduled day for a given date based on the plan start date.
  /// Returns null if the date is before the start or after the end.
  ReadingPlanDay? getScheduledDay(
    ReadingPlan plan,
    DateTime startDate,
    DateTime targetDate,
  ) {
    // Normalize dates to ignore time components
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final target = DateTime(targetDate.year, targetDate.month, targetDate.day);

    final difference = target.difference(start).inDays;

    // Day 1 is index 0 in difference (0 days since start = day 1)
    final dayNumber = difference + 1;

    if (dayNumber < 1 || dayNumber > plan.durationDays) {
      return null;
    }

    try {
      return plan.schedule.firstWhere((d) => d.day == dayNumber);
    } catch (_) {
      return null; // Day might not exist in schedule (e.g. rest days not in specific schedule list)
    }
  }
}
