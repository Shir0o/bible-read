import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/group_schedule.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';
import 'plan_pace.dart';

/// Persists the outcome of "Adjust pace" (#810).
///
/// A personal plan's schedule lives on the `custom_plans` document, so the
/// two options that re-shape it rewrite the plan in place — the same contract
/// as the edit flow: the document id is preserved so the reader's
/// `plan_progress` (and through it their completed days) survives.
///
/// A Shared plan's schedule belongs to the Group: one member must not move
/// the finish line for everyone else. So the adjusting reader's pace lives in
/// a private overlay at `users/{uid}/plan_pace/{groupId}`, which each of that
/// reader's views applies on top of the Group's schedule. The write path here
/// reaches nothing but the reader's own documents — the Group's schedule and
/// the other members' progress are untouched by construction.
class PlanPaceService {
  final FirebaseFirestore firestore;

  PlanPaceService({required this.firestore});

  /// Writes a personal plan's re-dated [adjusted] schedule onto its document.
  /// Completed days keep their dates under stretch and redistribution, so
  /// their day numbers — and the reader's `completedDays` — stay valid.
  Future<void> applyPersonalSchedule({
    required String uid,
    required ReadingPlan plan,
    required DateTime startDate,
    required List<GroupSchedule> adjusted,
  }) async {
    final updated = PlanPace.withAdjustedSchedule(plan, startDate, adjusted);
    await firestore
        .collection('custom_plans')
        .doc(plan.id)
        .set(
          {
            ...updated.toJson(),
            'userId': uid,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
  }

  /// Begin again for a personal plan: re-anchors the schedule so day one is
  /// [startDate] and drops the reader's completed day numbers, so day one is
  /// owed again. The Showing-up record — the per-user `reading` collection
  /// and the per-Group feed entries — lives outside `plan_progress` and is
  /// never touched here (#810; #790 story 9).
  Future<void> beginPersonalPlanAgain({
    required String uid,
    required ReadingPlan plan,
    required DateTime startDate,
    required UserPlanProgress progress,
  }) async {
    final adjusted = PlanPace.beginAgain(
      days: PlanPace.datedPersonalSchedule(plan, progress.startDate),
      startDate: startDate,
    );
    await applyPersonalSchedule(
      uid: uid,
      plan: plan,
      startDate: startDate,
      adjusted: adjusted,
    );

    final progressRef = firestore
        .collection('users')
        .doc(uid)
        .collection('plan_progress')
        .doc(plan.id);
    await progressRef.set({
      'planId': plan.id,
      'userId': uid,
      'startDate': Timestamp.fromDate(startDate),
      'completedDays': <int>[],
      if (progress.lastReadDate != null)
        'lastReadDate': Timestamp.fromDate(progress.lastReadDate!),
      'isArchived': progress.isArchived,
    });
  }

  /// Stores [adjusted] as this reader's private view of a Shared plan. The
  /// Group document, its `schedule` collection and every other member's
  /// progress are never written.
  Future<void> applySharedPlanOverlay({
    required String uid,
    required String groupId,
    required List<GroupSchedule> adjusted,
  }) async {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('plan_pace')
        .doc(groupId)
        .set({
      'groupId': groupId,
      // Dates as `YYYY-MM-DD` strings, matching the schedule-collection doc
      // ids — a Timestamp round-trips through UTC and shifts a local
      // midnight by the timezone offset.
      'days': [
        for (final day in adjusted)
          {'date': PlanPace.dateId(day.date), 'chapters': day.chapters},
      ],
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes the reader's Shared-plan overlay, restoring the Group's schedule
  /// as their view.
  Future<void> clearSharedPlanOverlay({
    required String uid,
    required String groupId,
  }) async {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('plan_pace')
        .doc(groupId)
        .delete();
  }

  /// The reader's stored overlay for [groupId], or null when they follow the
  /// Group's schedule as-is.
  Stream<List<GroupSchedule>?> sharedPlanOverlay(String uid, String groupId) {
    return firestore
        .collection('users')
        .doc(uid)
        .collection('plan_pace')
        .doc(groupId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      final raw = snap.data()?['days'] as List?;
      if (raw == null) return null;
      return [
        for (final entry in raw)
          GroupSchedule(
            date: DateTime.tryParse(entry['date'] as String? ?? '') ??
                DateTime.now(),
            chapters:
                (entry['chapters'] as List?)?.whereType<String>().toList() ??
                    <String>[],
          ),
      ];
    });
  }
}