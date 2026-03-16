import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';

class ReadingPlanService {
  final FirebaseFirestore firestore;

  ReadingPlanService({required this.firestore});

  // Cached plans to avoid repeated JSON parsing
  List<ReadingPlan>? _cachedPlans;

  /// Loads available reading plans from local assets and Firestore.
  Future<List<ReadingPlan>> getAvailablePlans({String? userId}) async {
    List<ReadingPlan> allPlans = [];

    // Load asset-based plans
    try {
      if (_cachedPlans == null) {
        final String jsonString =
            await rootBundle.loadString('assets/plans/sample_plans.json');
        final List<dynamic> jsonList = json.decode(jsonString);
        _cachedPlans =
            jsonList.map((json) => ReadingPlan.fromJson(json)).toList();
      }
      allPlans.addAll(_cachedPlans!);
    } catch (e) {
      if (kDebugMode) {
        print('Error loading asset reading plans: $e');
      }
    }

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

  /// Starts a reading plan for a user.
  Future<void> startPlan(String userId, String planId,
      {DateTime? startDate}) async {
    final progress = UserPlanProgress(
      planId: planId,
      userId: userId,
      startDate: startDate ?? DateTime.now(),
      completedDays: [],
    );

    await firestore
        .collection('users')
        .doc(userId)
        .collection('plan_progress')
        .doc(planId)
        .set(progress.toFirestore());
  }

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

  /// Streams all active plans for a user.
  Stream<List<UserPlanProgress>> getActivePlans(String userId) {
    return firestore
        .collection('users')
        .doc(userId)
        .collection('plan_progress')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => UserPlanProgress.fromFirestore(doc))
          .toList();
    });
  }

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
      ReadingPlan plan, DateTime startDate, DateTime targetDate) {
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
