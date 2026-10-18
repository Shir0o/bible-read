import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user_preferences.dart';
import '../widgets/burst_undo_controller.dart';
import '../widgets/sync_sheet.dart';
import 'coverage_ledger_service.dart';
import 'error_logger.dart';
import 'read_log_service.dart';
import 'read_through_coordinator.dart';
import 'reading_plan_service.dart';
import 'reading_status_service.dart';
import 'user_preferences_service.dart';

/// Deep in-process module owning the Showing-up daily habit lifecycle.
///
/// Encapsulates:
/// 1. Showing up directly (daily presence check-in and un-marking).
/// 2. Reading -> habit coupling (preferences check, one-time sync prompt, and
///    habit recording).
/// 3. Lap coverage credits for plan readings.
/// 4. Burst-aware habit management so rapid reading marks (and month-level marks)
///    coalesce cleanly, and reverting a burst rolls back today's habit record
///    if and only if that burst caused it (ADR-0005).
class HabitLifecycleService {
  HabitLifecycleService({
    required this.firestore,
    ReadLogService? readLogService,
    ReadingStatusService? readingStatusService,
    UserPreferencesService? preferencesService,
    ReadingPlanService? planService,
    ReadThroughCoordinator? readThroughCoordinator,
    CoverageLedgerService? coverageService,
  })  : readLogService = readLogService ?? ReadLogService(firestore: firestore),
        readingStatusService =
            readingStatusService ?? ReadingStatusService(firestore: firestore),
        preferencesService =
            preferencesService ?? UserPreferencesService(firestore: firestore),
        planService = planService ?? ReadingPlanService(firestore: firestore),
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
            );

  final FirebaseFirestore firestore;
  final ReadLogService readLogService;
  final ReadingStatusService readingStatusService;
  final UserPreferencesService preferencesService;
  final ReadingPlanService planService;
  final CoverageLedgerService coverageService;
  final ReadThroughCoordinator readThroughCoordinator;

  // Burst tracking state private to this coordinator instance.
  bool _habitBeforeBurst = false;
  bool _couplingFiredInBurst = false;
  bool _preparingBurst = false;

  /// Checks whether [uid] has already shown up on [date] (defaults to today).
  Future<bool> hasShownUp(String uid, {DateTime? date}) async {
    final targetDate = date ?? DateTime.now();
    final dateKey = ReadLogService.dateKeyFor(targetDate);
    try {
      final doc = await firestore
          .collection('users')
          .doc(uid)
          .collection('reading')
          .doc(dateKey)
          .get();
      return doc.exists && doc.data()?['read'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Records the reader as having shown up on [date] (defaults to today).
  ///
  /// Updates group feed entries and the per-user reading record via
  /// [ReadLogService], recalculates streak summary via [ReadingStatusService],
  /// and invalidates the reading status cache.
  Future<void> showUp(User user, {DateTime? date, String? reading}) async {
    final targetDate = date ?? DateTime.now();
    await readLogService.mark(user, date: targetDate, reading: reading);
    try {
      await readingStatusService.updateSummary();
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
    readingStatusService.invalidateCache();
  }

  /// Reverts the reader's shown-up record for [date] (defaults to today).
  ///
  /// Clears group feed entries and the per-user reading record via
  /// [ReadLogService], recalculates streak summary via [ReadingStatusService],
  /// and invalidates the reading status cache.
  Future<void> clearShowingUp(User user, {DateTime? date}) async {
    final targetDate = date ?? DateTime.now();
    await readLogService.clear(user, date: targetDate);
    try {
      await readingStatusService.updateSummary();
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
    readingStatusService.invalidateCache();
  }

  /// Honors the one-directional reading -> habit coupling after a plan or group
  /// reading is marked. Asks once via [SyncSheet], then respects saved preference.
  ///
  /// Best-effort: errors are logged (and surfaced via [onMessage] when given)
  /// without rethrowing. Returns whether today's habit was recorded.
  Future<bool> maybeCoupleHabit({
    required BuildContext context,
    required User user,
    void Function(String message)? onMessage,
  }) async {
    UserPreferences prefs;
    try {
      prefs = await preferencesService.fetchPreferences(user.uid);
    } catch (e, st) {
      ErrorLogger.log(e, st);
      return false;
    }

    if (!prefs.syncPromptAnswered) {
      if (!context.mounted) return false;
      final choice = await SyncSheet.show(context);
      final linked = choice == true;
      try {
        await preferencesService.updatePreferences(
          user.uid,
          prefs.copyWith(autoMarkPlanRead: linked, syncPromptAnswered: true),
        );
      } catch (e, st) {
        ErrorLogger.log(e, st);
        onMessage?.call(
          "Couldn't save your choice. We'll ask again next time.",
        );
      }
      if (linked) return _recordHabitForToday(user, onMessage);
      return false;
    } else if (prefs.autoMarkPlanRead) {
      return _recordHabitForToday(user, onMessage);
    }
    return false;
  }

  Future<bool> _recordHabitForToday(
    User user,
    void Function(String message)? onMessage,
  ) async {
    try {
      await showUp(user);
      return true;
    } catch (e, st) {
      ErrorLogger.log(e, st);
      onMessage?.call(
        "Saved your reading, but couldn't mark you as showing up today.",
      );
      return false;
    }
  }

  /// Marks [day] of [planId] complete, credits testament laps, and couples the
  /// habit according to user preference.
  ///
  /// Throws if [planService.markDayComplete] fails so caller can revert
  /// optimistic UI. Coupling is best-effort. Returns whether habit was recorded.
  Future<bool> completePlanDay({
    required BuildContext context,
    required User user,
    required String planId,
    required int day,
    void Function(String message)? onMessage,
  }) async {
    await planService.markDayComplete(user.uid, planId, day);
    await coverageService.creditPlanDay(
      uid: user.uid,
      planId: planId,
      day: day,
    );
    if (!context.mounted) return false;
    return maybeCoupleHabit(
      context: context,
      user: user,
      onMessage: onMessage,
    );
  }

  /// Credits [days] of [planId] to testament laps silently (ADR-0005 starting point).
  Future<void> creditPlanDaysSilently({
    required String uid,
    required String planId,
    required Iterable<int> days,
  }) async {
    for (final day in days) {
      await coverageService.creditPlanDaySilently(
        uid: uid,
        planId: planId,
        day: day,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Burst-aware habit management (ADR-0005)
  // ---------------------------------------------------------------------------

  Future<void> _prepareBurstIfNeeded(
    User user,
    BurstUndoController burstController,
  ) async {
    if (burstController.count == 0 && !_preparingBurst) {
      _preparingBurst = true;
      try {
        _habitBeforeBurst = await hasShownUp(user.uid);
        _couplingFiredInBurst = false;
      } finally {
        _preparingBurst = false;
      }
    }
  }

  Future<void>? _lastBurstUndoFuture;

  /// In-flight or most recent habit rollback Future triggered by burst undo.
  Future<void>? get lastBurstUndoFuture => _lastBurstUndoFuture;

  void _handleBurstUndo(VoidCallback onUndo, User user) {
    onUndo();
    if (_couplingFiredInBurst && !_habitBeforeBurst) {
      _couplingFiredInBurst = false;
      _lastBurstUndoFuture = clearShowingUp(user);
    }
  }

  /// Registers an undo action in [burstController] during a burst without
  /// performing immediate coupling (e.g. during a loop in month-marking).
  Future<void> registerBurstMark({
    required BuildContext context,
    required User user,
    required BurstUndoController burstController,
    required VoidCallback onUndo,
  }) async {
    await _prepareBurstIfNeeded(user, burstController);
    if (!context.mounted) return;
    burstController.add(context, () => _handleBurstUndo(onUndo, user));
  }

  /// Performs habit coupling within a burst, wrapping [onUndo] with automatic
  /// habit reversion if this burst causes today's habit to be recorded.
  Future<bool> coupleWithBurst({
    required BuildContext context,
    required User user,
    required BurstUndoController burstController,
    required VoidCallback onUndo,
    void Function(String message)? onMessage,
  }) async {
    await _prepareBurstIfNeeded(user, burstController);
    if (!context.mounted) return false;
    burstController.add(context, () => _handleBurstUndo(onUndo, user));

    if (!context.mounted) return false;
    final coupled = await maybeCoupleHabit(
      context: context,
      user: user,
      onMessage: burstController.count > 1 ? null : onMessage,
    );
    if (coupled) {
      _couplingFiredInBurst = true;
    }
    return coupled;
  }

  /// Marks a plan day complete and applies burst-aware habit coupling.
  Future<bool> completePlanDayWithBurst({
    required BuildContext context,
    required User user,
    required String planId,
    required int day,
    required BurstUndoController burstController,
    required VoidCallback onUndo,
    void Function(String message)? onMessage,
  }) async {
    await planService.markDayComplete(user.uid, planId, day);
    await coverageService.creditPlanDay(
      uid: user.uid,
      planId: planId,
      day: day,
    );
    if (!context.mounted) return false;
    return coupleWithBurst(
      context: context,
      user: user,
      burstController: burstController,
      onUndo: onUndo,
      onMessage: onMessage,
    );
  }

  /// Couples the habit once silently at the end of a whole-month burst mark.
  Future<bool> coupleMonthWithBurst({
    required BuildContext context,
    required User user,
    required BurstUndoController burstController,
  }) async {
    if (!context.mounted) return false;
    final coupled = await maybeCoupleHabit(
      context: context,
      user: user,
    );
    if (coupled) {
      _couplingFiredInBurst = true;
    }
    return coupled;
  }
}
