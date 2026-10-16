import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/group_schedule.dart';
import 'coverage_ledger_service.dart';
import 'lap_progress_service.dart';
import 'milestone_announcer.dart';
import 'reading_plan_service.dart';

/// Credits reading to the user's testament laps from the two places a user can
/// mark: a group schedule and a personal reading plan.
///
/// Delegates to [CoverageLedgerService], which unifies lap progress, read-through
/// ledger, and coverage crediting across all surfaces.
class ReadThroughCoordinator {
  ReadThroughCoordinator({
    FirebaseFirestore? firestore,
    LapProgressService? lapService,
    ReadingPlanService? planService,
    MilestoneAnnouncer? announcer,
    CoverageLedgerService? coverageLedgerService,
  })  : coverageLedgerService = coverageLedgerService ??
            CoverageLedgerService(
              firestore: firestore,
              lapService: lapService,
              planService: planService,
              announcer: announcer,
            ),
        announcer = announcer ??
            (coverageLedgerService?.announcer ??
                MilestoneAnnouncer(
                  firestore: firestore ?? FirebaseFirestore.instance,
                )),
        lapService = lapService ??
            (coverageLedgerService?.lapService ??
                LapProgressService(
                  firestore: firestore ?? FirebaseFirestore.instance,
                )),
        planService = planService ??
            (coverageLedgerService?.planService ??
                ReadingPlanService(
                  firestore: firestore ?? FirebaseFirestore.instance,
                ));

  final CoverageLedgerService coverageLedgerService;
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
  }) =>
      coverageLedgerService.creditGroupReading(
        uid: uid,
        schedule: schedule,
        checkedIndices: checkedIndices,
      );

  /// Credits every chapter scheduled for [day] of [planId].
  ///
  /// Plan progress is stored per day, not per chapter, so finishing a day
  /// credits everything that day listed — which is what the user asserted when
  /// they marked it.
  Future<void> creditPlanDay({
    required String uid,
    required String planId,
    required int day,
  }) =>
      coverageLedgerService.creditPlanDay(
        uid: uid,
        planId: planId,
        day: day,
      );

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
  }) =>
      coverageLedgerService.creditPlanDaySilently(
        uid: uid,
        planId: planId,
        day: day,
      );
}
