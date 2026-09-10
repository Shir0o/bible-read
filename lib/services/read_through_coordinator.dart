import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/group_schedule.dart';
import '../models/reading_plan.dart';
import 'error_logger.dart';
import 'lap_progress_service.dart';
import 'milestone_announcer.dart';
import 'reading_plan_service.dart';

/// Credits reading to the user's testament laps from the two places a user can
/// mark: a group schedule and a personal reading plan.
///
/// Both surfaces record *what* was read at different resolutions — a group
/// entry checks individual chapters, a plan marks a whole day — so this is
/// where each is turned into the same thing: a list of chapter references.
///
/// Every method is best-effort. Reading is already recorded by the time these
/// run, and a lap that misses a credit is a smaller problem than a marking that
/// fails, so failures are logged and swallowed.
class ReadThroughCoordinator {
  ReadThroughCoordinator({
    FirebaseFirestore? firestore,
    LapProgressService? lapService,
    ReadingPlanService? planService,
    MilestoneAnnouncer? announcer,
  })  : announcer = announcer ??
            MilestoneAnnouncer(
              firestore: firestore ?? FirebaseFirestore.instance,
            ),
        lapService = lapService ??
            LapProgressService(
              firestore: firestore ?? FirebaseFirestore.instance,
            ),
        planService = planService ??
            ReadingPlanService(
              firestore: firestore ?? FirebaseFirestore.instance,
            );

  final LapProgressService lapService;
  final ReadingPlanService planService;

  /// Puts a detected read-through in the feed.
  final MilestoneAnnouncer announcer;

  /// Credits the chapters a user just checked off in a group schedule.
  ///
  /// [checkedIndices] indexes into [schedule].chapters. A schedule with no
  /// chapters is a bare "did you show up today" day and credits nothing.
  Future<void> creditGroupReading({
    required String uid,
    required GroupSchedule schedule,
    required Iterable<int> checkedIndices,
  }) async {
    final chapters = schedule.chapters;
    if (chapters.isEmpty) return;

    final references = <String>[];
    for (final index in checkedIndices) {
      if (index < 0 || index >= chapters.length) continue;
      references.add(chapters[index]);
    }
    await _credit(uid, references);
  }

  /// Credits every chapter scheduled for [day] of [planId].
  ///
  /// Plan progress is stored per day, not per chapter, so finishing a day
  /// credits everything that day listed — which is what the user asserted when
  /// they marked it.
  Future<void> creditPlanDay({
    required String uid,
    required String planId,
    required int day,
  }) async {
    try {
      final plan = await planService.getPlanById(planId, userId: uid);
      if (plan == null) return;
      await _credit(uid, _readingsForDay(plan, day));
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  /// Credits [day] of [planId] without announcing any completed Read-Through
  /// (ADR-0005).
  ///
  /// Used by the Starting point: the day is a claim about reading done before
  /// the app, so a Read-Through it completes must be silent, like a Backfilled
  /// Read-Through — never a Milestone.
  Future<void> creditPlanDaySilently({
    required String uid,
    required String planId,
    required int day,
  }) async {
    try {
      final plan = await planService.getPlanById(planId, userId: uid);
      if (plan == null) return;
      await _creditSilently(uid, _readingsForDay(plan, day));
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  /// The chapter references [plan] schedules for [day].
  static List<String> _readingsForDay(ReadingPlan plan, int day) {
    for (final entry in plan.schedule) {
      if (entry.day == day) return entry.readings;
    }
    return const [];
  }

  Future<void> _credit(String uid, List<String> references) async {
    if (references.isEmpty) return;
    try {
      final result = await lapService.recordChapters(uid, references);
      if (result.isMilestone) {
        await announcer.announce(uid: uid, completed: result.completed);
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  /// Like [_credit] but never announces: the chapters are a claim about the
  /// past (ADR-0005), so any Read-Through they complete stays silent.
  Future<void> _creditSilently(String uid, List<String> references) async {
    if (references.isEmpty) return;
    try {
      await lapService.recordChapters(uid, references);
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }
}
