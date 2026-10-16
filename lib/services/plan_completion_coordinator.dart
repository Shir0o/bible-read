import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'coverage_ledger_service.dart';
import 'habit_lifecycle_service.dart';
import 'read_through_coordinator.dart';
import 'reading_plan_service.dart';
import 'reading_status_service.dart';
import 'user_preferences_service.dart';

/// Shared owner of the one-directional, opt-in coupling between finishing a
/// *plan reading* and recording the daily *habit* ("showing up").
///
/// Delegates to [HabitLifecycleService], which provides the deep in-process
/// lifecycle for Showing up and reading->habit coupling across the app.
class PlanCompletionCoordinator {
  final FirebaseFirestore firestore;
  final ReadingPlanService planService;
  final UserPreferencesService preferencesService;
  final CoverageLedgerService coverageService;
  final ReadThroughCoordinator readThroughCoordinator;
  final ReadingStatusService? readingStatusService;
  final HabitLifecycleService _habitService;

  PlanCompletionCoordinator({
    required this.firestore,
    ReadingPlanService? planService,
    UserPreferencesService? preferencesService,
    ReadThroughCoordinator? readThroughCoordinator,
    CoverageLedgerService? coverageService,
    this.readingStatusService,
    HabitLifecycleService? habitService,
  })  : planService = planService ?? ReadingPlanService(firestore: firestore),
        preferencesService =
            preferencesService ?? UserPreferencesService(firestore: firestore),
        coverageService = coverageService ??
            (readThroughCoordinator?.coverageLedgerService ??
                CoverageLedgerService(
                  firestore: firestore,
                  planService: planService,
                )),
        readThroughCoordinator = readThroughCoordinator ??
            ReadThroughCoordinator(
              firestore: firestore,
              planService: planService,
              coverageLedgerService: coverageService,
            ),
        _habitService = habitService ??
            HabitLifecycleService(
              firestore: firestore,
              planService: planService,
              preferencesService: preferencesService,
              readThroughCoordinator: readThroughCoordinator,
              coverageService: coverageService,
              readingStatusService: readingStatusService,
            );

  /// Marks [day] of [planId] complete, then honors the reading → habit coupling.
  Future<bool> completePlanDay({
    required BuildContext context,
    required User user,
    required String planId,
    required int day,
    void Function(String message)? onMessage,
  }) =>
      _habitService.completePlanDay(
        context: context,
        user: user,
        planId: planId,
        day: day,
        onMessage: onMessage,
      );

  /// Honors the one-directional reading→habit coupling after a reading is finished.
  Future<bool> maybeCoupleHabit({
    required BuildContext context,
    required User user,
    void Function(String message)? onMessage,
  }) =>
      _habitService.maybeCoupleHabit(
        context: context,
        user: user,
        onMessage: onMessage,
      );

  /// Credits [days] of [planId] to testament laps silently (ADR-0005).
  Future<void> creditPlanDaysSilently({
    required String uid,
    required String planId,
    required Iterable<int> days,
  }) =>
      _habitService.creditPlanDaysSilently(
        uid: uid,
        planId: planId,
        days: days,
      );
}
