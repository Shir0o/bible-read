import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user_preferences.dart';
import '../pages/read_log_page.dart';
import '../widgets/sync_sheet.dart';
import 'error_logger.dart';
import 'reading_plan_service.dart';
import 'user_preferences_service.dart';

/// Shared owner of the one-directional, opt-in coupling between finishing a
/// *plan reading* and recording the daily *habit* ("showing up").
///
/// The coupling rule (epic #716, issue #717): completing a plan reading may
/// optionally also count as showing up for the day. The choice is asked once
/// via [SyncSheet], saved to [UserPreferences], and changeable in Settings. The
/// bare daily-habit tap never advances a plan — coupling only flows reading →
/// habit, never the reverse, and never on un-marking.
///
/// Both [PlanDetailPage] and the Home "Today's reading" card route through this
/// so the semantics stay identical in both places.
class PlanCompletionCoordinator {
  final FirebaseFirestore firestore;
  final ReadingPlanService planService;
  final UserPreferencesService preferencesService;

  PlanCompletionCoordinator({
    required this.firestore,
    ReadingPlanService? planService,
    UserPreferencesService? preferencesService,
  })  : planService =
            planService ?? ReadingPlanService(firestore: firestore),
        preferencesService =
            preferencesService ?? UserPreferencesService(firestore: firestore);

  /// Marks [day] of [planId] complete, then honors the reading → habit coupling.
  ///
  /// Throws if the underlying [ReadingPlanService.markDayComplete] write fails so
  /// callers can roll back optimistic UI; the coupling step is best-effort and
  /// never throws.
  Future<void> completePlanDay({
    required BuildContext context,
    required User user,
    required String planId,
    required int day,
  }) async {
    await planService.markDayComplete(user.uid, planId, day);
    if (!context.mounted) return;
    await maybeCoupleHabit(context: context, user: user);
  }

  /// Honors the one-directional reading→habit coupling after a reading is
  /// finished. Asks once via [SyncSheet], then respects the saved preference.
  ///
  /// Best-effort: failures are logged (and surfaced via [onMessage] when given)
  /// but never thrown — a reading is already recorded by the time this runs.
  Future<void> maybeCoupleHabit({
    required BuildContext context,
    required User user,
    void Function(String message)? onMessage,
  }) async {
    UserPreferences prefs;
    try {
      prefs = await preferencesService.fetchPreferences(user.uid);
    } catch (e, st) {
      ErrorLogger.log(e, st);
      return;
    }

    if (!prefs.syncPromptAnswered) {
      if (!context.mounted) return;
      final choice = await SyncSheet.show(context);
      final linked = choice == true;
      try {
        await preferencesService.updatePreferences(
          user.uid,
          prefs.copyWith(autoMarkPlanRead: linked, syncPromptAnswered: true),
        );
      } catch (e, st) {
        ErrorLogger.log(e, st);
        // The choice didn't save, so the prompt may reappear — let the user
        // know rather than failing silently.
        onMessage?.call("Couldn't save your choice. We'll ask again next time.");
      }
      if (linked) await _recordHabitForToday(user, onMessage);
    } else if (prefs.autoMarkPlanRead) {
      await _recordHabitForToday(user, onMessage);
    }
  }

  /// Records the daily habit ("showing up") for today, equivalent to tapping
  /// "I read today" on Home. Idempotent; surfaces a gentle notice on failure.
  Future<void> _recordHabitForToday(
    User user,
    void Function(String message)? onMessage,
  ) async {
    try {
      await ReadLogPage.writeReadLogEntry(user, firestore: firestore);
    } catch (e, st) {
      ErrorLogger.log(e, st);
      onMessage?.call(
        "Saved your reading, but couldn't mark you as showing up today.",
      );
    }
  }
}
