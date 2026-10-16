import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

import '../../models/group.dart';
import '../../models/group_member_progress.dart';
import '../../models/reading_plan_progress.dart';
import '../../services/active_reading_aggregator.dart';
import '../../services/catch_up_engine.dart';
import '../../services/error_logger.dart';
import '../../services/nudge_service.dart';
import '../../services/group_service.dart';
import '../../services/reading_plan_service.dart';
import '../../services/user_preferences_service.dart';
import '../../services/vibration_service.dart';
import '../catch_up_status_row.dart';
import '../member_presence_stack.dart';
import '../../pages/adjust_pace_page.dart';
import '../../pages/create_plan_page.dart';
import '../../pages/group_members_page.dart';
import '../../pages/plan_detail_page.dart';
import '../../pages/recently_deleted_page.dart';
import '../../services/plan_pace_service.dart';
import '../skeleton_loader.dart';
import '../skeletons/plans_hub_skeleton.dart';

/// The Path tab's plan hub — a single list of *everything* the user is
/// reading: their personal plans ("On your own") and the Shared plans of
/// Groups they belong to ("Together"), each as a rich card tagged with its
/// lifecycle state, with per-card actions (continue, pin as Home primary,
/// edit, leave/manage). Completed plans collapse into a "Finished" list and
/// left (archived) plans into an "Archived" list with restore and permanent
/// delete. Embedded in [JourneyPage]; there is no pushed "My Reading Plans"
/// page and no duplicate of it anywhere (#808, #811).
class PlansHub extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final GroupService groupService;
  final ReadingPlanService readingPlanService;
  final UserPreferencesService userPreferencesService;
  final VibrationService vibrationService;
  final DateTime Function() dateProvider;
  final ActiveReadingAggregator? activeReadingAggregator;

  const PlansHub({
    super.key,
    required this.firestore,
    required this.auth,
    required this.groupService,
    required this.readingPlanService,
    required this.userPreferencesService,
    required this.vibrationService,
    required this.dateProvider,
    this.activeReadingAggregator,
  });

  @override
  State<PlansHub> createState() => PlansHubState();
}

class PlansHubState extends State<PlansHub> {
  bool _loading = true;
  List<ActivePersonalReading> _personal = [];
  List<ActivePersonalReading> _archived = [];
  List<Group> _archivedGroups = [];
  int _trashedCount = 0;
  List<ActiveGroupReading> _groups = [];
  String? _pinnedReadingId;

  late final ActiveReadingAggregator _aggregator;

  /// Whether the Archived section lists every row, not just the first few.
  bool _showAllArchived = false;

  final Set<StreamSubscription<dynamic>> _watchSubs = {};
  Timer? _reloadTimer;
  bool _watchStarted = false;
  bool _loadInFlight = false;
  bool _reloadQueued = false;

  @override
  void initState() {
    super.initState();
    _aggregator = widget.activeReadingAggregator ??
        ActiveReadingAggregator(
          readingPlanService: widget.readingPlanService,
          groupService: widget.groupService,
          paceService: PlanPaceService(firestore: widget.firestore),
          userPreferencesService: widget.userPreferencesService,
          dateProvider: widget.dateProvider,
          firestore: widget.firestore,
        );
    _load().whenComplete(() {
      if (mounted) _startWatching();
    });
  }

  Future<void> _load() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (_loadInFlight) {
      _reloadQueued = true;
      return;
    }
    _loadInFlight = true;

    final today = widget.dateProvider();

    try {
      // Pinned-reading preference (best-effort).
      String? pinned;
      try {
        final prefs = await widget.userPreferencesService.fetchPreferences(uid);
        pinned = prefs.pinnedReadingId;
      } catch (e, st) {
        ErrorLogger.log(e, st);
      }

      // Active readings (personal plans + group schedules) via deep aggregator
      final snapshot = await _aggregator.fetch(
        uid,
        today: today,
        pinnedReadingId: pinned,
      );

      // Left (archived) personal plans via aggregator
      final archived = await _aggregator.fetchArchivedPlans(uid, today: today);

      // Archived groups (#776): owned-and-archived, or participation the
      // reader shelved. Both return via the Archive rows below.
      List<Group> archivedGroups = const [];
      try {
        archivedGroups =
            await widget.groupService.archivedGroupsForUser(uid).timeout(
                  const Duration(seconds: 5),
                  onTimeout: () => const <Group>[],
                );
      } catch (e, st) {
        ErrorLogger.log(e, st);
      }

      // Count of everything sitting in the Recently Deleted hub, so the
      // shortcut can hint there is something waiting (#776).
      int trashedCount = 0;
      try {
        final trashedPlans =
            await widget.readingPlanService.getDeletedPlans(uid).first.timeout(
                  const Duration(seconds: 5),
                  onTimeout: () => const <UserPlanProgress>[],
                );
        final trashedGroups =
            await widget.groupService.getDeletedGroups(uid).first.timeout(
                  const Duration(seconds: 5),
                  onTimeout: () => const <Group>[],
                );
        trashedCount = trashedPlans.length + trashedGroups.length;
      } catch (e, st) {
        ErrorLogger.log(e, st);
      }

      if (mounted) {
        setState(() {
          _personal = snapshot.personalPlans;
          _archived = archived;
          _archivedGroups = archivedGroups;
          _trashedCount = trashedCount;
          _groups = snapshot.groupReadings;
          _pinnedReadingId = pinned;
          _loading = false;
        });
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) setState(() => _loading = false);
    } finally {
      _loadInFlight = false;
      if (_reloadQueued) {
        _reloadQueued = false;
        _scheduleReload();
      }
    }
  }

  void _startWatching() {
    if (_watchStarted) return;
    _watchStarted = true;
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;

    _watchSubs.add(
      _aggregator
          .watch(
            uid,
            dateProvider: widget.dateProvider,
            pinnedReadingId: _pinnedReadingId,
          )
          .listen(
            (_) => _scheduleReload(),
            onError: (Object e, StackTrace st) => ErrorLogger.log(e, st),
          ),
    );

    _listen(widget.readingPlanService.getArchivedPlans(uid));
    _listen(widget.readingPlanService.getDeletedPlans(uid));
    _listen(widget.groupService.getDeletedGroups(uid));
  }

  void _listen(Stream<dynamic> stream) {
    var first = true;
    _watchSubs.add(stream.listen(
      (_) {
        if (first) {
          first = false;
          return;
        }
        _scheduleReload();
      },
      onError: (Object e, StackTrace st) => ErrorLogger.log(e, st),
    ));
  }

  void _scheduleReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(
      const Duration(milliseconds: 300),
      () {
        if (mounted) unawaited(_load());
      },
    );
  }

  @override
  void dispose() {
    _reloadTimer?.cancel();
    for (final subscription in _watchSubs) {
      subscription.cancel();
    }
    super.dispose();
  }

  /// Reloads the hub's plan lists. Called by the embedding page's
  /// RefreshIndicator so a pull refreshes the whole tab.
  Future<void> reload() => _load();

  // ---- Actions ------------------------------------------------------------

  Future<void> _togglePin(String pinKey) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    widget.vibrationService.lightImpact();
    final previous = _pinnedReadingId;
    final next = _pinnedReadingId == pinKey ? null : pinKey;
    // Optimistic.
    setState(() => _pinnedReadingId = next);
    try {
      final prefs = await widget.userPreferencesService.fetchPreferences(uid);
      await widget.userPreferencesService.updatePreferences(
        uid,
        next == null
            ? prefs.copyWith(clearPinnedReadingId: true)
            : prefs.copyWith(pinnedReadingId: next),
      );
    } catch (e, st) {
      ErrorLogger.log(e, st);
      // Roll back so the card doesn't show a pin that wasn't persisted.
      if (mounted) {
        setState(() => _pinnedReadingId = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't update your pin")),
        );
      }
    }
  }

  Future<void> _editPlan(ActivePersonalReading row) async {
    widget.vibrationService.lightImpact();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreatePlanPage(
          firestore: widget.firestore,
          auth: widget.auth,
          vibrationService: widget.vibrationService,
          editingPlan: row.plan,
          editingProgress: row.progress,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  /// Adjust pace on a personal plan (#810): the three options run against
  /// the plan's dated schedule, and the chosen one is persisted in place.
  Future<void> _adjustPersonalPace(ActivePersonalReading row) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    final applied = await adjustPersonalPace(
      context,
      firestore: widget.firestore,
      uid: uid,
      plan: row.plan,
      progress: row.progress,
      today: widget.dateProvider(),
      vibrationService: widget.vibrationService,
    );
    if (applied && mounted) await _load();
  }

  /// Adjust pace on a Shared plan (#810): the arithmetic runs on the Group's
  /// schedule, but the outcome is stored as the reader's own overlay — the
  /// Group's schedule and the other members' progress are never written.
  Future<void> _adjustSharedPace(ActiveGroupReading row) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    final applied = await adjustSharedPace(
      context,
      firestore: widget.firestore,
      uid: uid,
      groupId: row.group.id,
      schedule: row.schedule,
      completedDateIds: row.completedDateIds,
      daysBehind: row.status.missedCount,
      today: widget.dateProvider(),
      vibrationService: widget.vibrationService,
    );
    if (applied && mounted) await _load();
  }

  /// Archives a plan straight away — it is fully reversible, so an Undo
  /// snackbar stands in for a confirmation step.
  Future<void> _archivePlan(ActivePersonalReading row) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    widget.vibrationService.lightImpact();
    try {
      await widget.readingPlanService.setPlanArchived(uid, row.plan.id, true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Archived "${row.plan.title}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _restorePlan(row),
          ),
        ),
      );
      await _load();
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to archive "${row.plan.title}". Please try again.'),
          ),
        );
      }
    }
  }

  void _setPersonalFinished(ActivePersonalReading row, bool finished) {
    final i = _personal.indexWhere((r) => r.plan.id == row.plan.id);
    if (i < 0) return;
    setState(
      () => _personal = [..._personal]..[i] = row.withFinished(finished),
    );
  }

  void _setGroupFinished(ActiveGroupReading row, bool finished) {
    final i = _groups.indexWhere((r) => r.group.id == row.group.id);
    if (i < 0) return;
    setState(() => _groups = [..._groups]..[i] = row.withFinished(finished));
  }

  /// Finishes an ended plan straight away (ADR-0010) — it is fully
  /// reversible, so an Undo snackbar stands in for a confirmation step. The
  /// plan moves to Finished at once and rolls back if the write fails.
  Future<void> _finishPlan(ActivePersonalReading row) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    widget.vibrationService.lightImpact();
    _setPersonalFinished(row, true);
    try {
      await widget.readingPlanService.finishPlan(uid, row.plan.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Finished "${row.plan.title}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _unfinishPlan(row),
          ),
        ),
      );
      await _load();
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        _setPersonalFinished(row, false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to finish "${row.plan.title}". Please try again.',
            ),
          ),
        );
      }
    }
  }

  /// Restores a finished plan to where it was — ended, same readings marked.
  Future<void> _unfinishPlan(ActivePersonalReading row) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    widget.vibrationService.lightImpact();
    _setPersonalFinished(row, false);
    try {
      await widget.readingPlanService.unfinishPlan(uid, row.plan.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"${row.plan.title}" restored')));
      await _load();
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        _setPersonalFinished(row, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to restore "${row.plan.title}". Please try again.',
            ),
          ),
        );
      }
    }
  }

  /// Finishes the reader's own participation in an ended Shared plan
  /// (ADR-0010). The Group schedule and the other members carry on.
  Future<void> _finishGroup(ActiveGroupReading row) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    widget.vibrationService.lightImpact();
    _setGroupFinished(row, true);
    try {
      await widget.groupService.finishMemberParticipation(
        groupId: row.group.id,
        uid: uid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Finished "${row.group.name}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _unfinishGroup(row),
          ),
        ),
      );
      await _load();
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        _setGroupFinished(row, false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to finish "${row.group.name}". Please try again.',
            ),
          ),
        );
      }
    }
  }

  /// Restores a finished Shared plan — it returns with the Group's current
  /// dates, which may have moved since the reader finished.
  Future<void> _unfinishGroup(ActiveGroupReading row) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    widget.vibrationService.lightImpact();
    _setGroupFinished(row, false);
    try {
      await widget.groupService.unfinishMemberParticipation(
        groupId: row.group.id,
        uid: uid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"${row.group.name}" restored')));
      await _load();
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        _setGroupFinished(row, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to restore "${row.group.name}". Please try again.',
            ),
          ),
        );
      }
    }
  }

  /// Restores a left plan to active — it reappears in "On your own".
  Future<void> _restorePlan(ActivePersonalReading row) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    widget.vibrationService.lightImpact();
    try {
      await widget.readingPlanService.setPlanArchived(uid, row.plan.id, false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${row.plan.title}" restored to active')),
      );
      await _load();
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to restore "${row.plan.title}". Please try again.'),
          ),
        );
      }
    }
  }

  /// Unarchives a group (#776): an owned group returns for every member; a
  /// shelved participation returns to this reader's active lists.
  Future<void> _unarchiveGroup(Group group) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    widget.vibrationService.lightImpact();
    try {
      if (uid == group.ownerUid) {
        await widget.groupService.unarchiveGroup(
          groupId: group.id,
          ownerUid: uid,
        );
      } else {
        await widget.groupService.unarchiveMemberParticipation(
          groupId: group.id,
          uid: uid,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${group.name}" restored')),
      );
      await _load();
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Failed to restore "${group.name}". Please try again.'),
          ),
        );
      }
    }
  }

  /// Asks before the owner soft-deletes the group — recoverable for 30 days
  /// from the Recently Deleted hub.
  void _confirmTrashGroup(Group group) {
    showDialog(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${group.name}"?'),
        content: const Text(
          'The group moves to Recently Deleted for 30 days. Members lose '
          'access until you restore it or the 30 days run out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _trashGroup(group);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _trashGroup(Group group) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    widget.vibrationService.lightImpact();
    try {
      await widget.groupService.softDeleteGroup(
        groupId: group.id,
        ownerUid: uid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${group.name}" moved to Recently Deleted')),
      );
      await _load();
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Failed to delete "${group.name}". Please try again.'),
          ),
        );
      }
    }
  }

  /// Opens the Recently Deleted hub (#776).
  void _openTrash() {
    widget.vibrationService.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecentlyDeletedPage(
          firestore: widget.firestore,
          auth: widget.auth,
          groupService: widget.groupService,
          readingPlanService: widget.readingPlanService,
          vibrationService: widget.vibrationService,
          dateProvider: widget.dateProvider,
        ),
      ),
    );
  }

  /// Moves a plan to the Recently Deleted hub (#776): recoverable for 30
  /// days, restorable to the state it had — archived or active.
  Future<void> _trashPlan(ActivePersonalReading row) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    widget.vibrationService.lightImpact();
    try {
      await widget.readingPlanService.softDeletePlan(uid, row.plan.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('"${row.plan.title}" moved to Recently Deleted')),
      );
      await _load();
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Failed to delete "${row.plan.title}". Please try again.'),
          ),
        );
      }
    }
  }

  /// Asks before moving the plan to the trash — recoverable for 30 days.
  void _confirmTrashPlan(ActivePersonalReading row) {
    showDialog(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${row.plan.title}"?'),
        content: const Text(
          'It moves to Recently Deleted and waits there for 30 days. '
          'Restore it any time before then.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _trashPlan(row);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _continuePlan(ActivePersonalReading row) {
    widget.vibrationService.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlanDetailPage(
          plan: row.plan,
          firestore: widget.firestore,
          auth: widget.auth,
          initialProgress: row.progress,
          vibrationService: widget.vibrationService,
        ),
      ),
    );
  }

  void _manageGroup(ActiveGroupReading row) {
    widget.vibrationService.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupMembersPage(
          group: row.group,
          groupService: widget.groupService,
          nudgeService: NudgeService(firestore: widget.firestore),
          auth: widget.auth,
          vibrationService: widget.vibrationService,
        ),
      ),
    );
  }

  void _reviewGroup(ActiveGroupReading row) {
    widget.vibrationService.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlanDetailPage(
          group: row.group,
          groupService: widget.groupService,
          auth: widget.auth,
          vibrationService: widget.vibrationService,
          initialSchedule: row.schedule,
          isMember: true,
        ),
      ),
    );
  }

  Future<void> _enroll() async {
    widget.vibrationService.lightImpact();

    // One creation flow, no modal fork (#809): what to read and over how
    // long come first, who is reading is a field inside the form. The create
    // page replaces itself with a detail page on success (pushReplacement),
    // so the push future can't reliably report whether a plan was created.
    // Reload on return so a newly created plan/group always shows in the
    // hub; the occasional wasted reload on cancel is cheap.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreatePlanPage(
          firestore: widget.firestore,
          auth: widget.auth,
          vibrationService: widget.vibrationService,
          groupService: widget.groupService,
        ),
      ),
    );
    if (mounted) await _load();
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Finished lists both fully-read plans and ones the reader Finished
    // early (ADR-0010); `state` alone no longer says which.
    bool isDone(PlanLifecycle state, bool finished) =>
        state == PlanLifecycle.complete || finished;
    final personalActive =
        _personal.where((r) => !isDone(r.state, r.finished)).toList();
    final personalDone =
        _personal.where((r) => isDone(r.state, r.finished)).toList();
    final groupActive =
        _groups.where((r) => !isDone(r.state, r.finished)).toList();
    final groupDone =
        _groups.where((r) => isDone(r.state, r.finished)).toList();
    final totalActive = personalActive.length + groupActive.length;
    final hasFinished = personalDone.isNotEmpty || groupDone.isNotEmpty;
    final nothing = totalActive == 0 &&
        !hasFinished &&
        _archived.isEmpty &&
        _archivedGroups.isEmpty;

    if (!_loading && nothing) return _emptyState(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.hPadding, 4, AppSpacing.hPadding, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The enroll CTA sits at the top of the list, right under the
          // header, so it is never below the fold and no bottom-anchored
          // toast can cover it (ADR-0005).
          const SizedBox(height: AppSpacing.gap8),
          _enrollButton(context),
          SkeletonLoader(
            loading: _loading,
            minTime: const Duration(milliseconds: 1000),
            skeleton: const PlansHubSkeleton(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                if (personalActive.isNotEmpty) ...[
                  _sectionHeading(
                    context,
                    icon: Icons.explore_outlined,
                    title: 'On your own',
                  ),
                  for (final row in personalActive) _personalCard(context, row),
                ],
                if (groupActive.isNotEmpty) ...[
                  SizedBox(
                      height: personalActive.isNotEmpty ? AppSpacing.gap16 : 0),
                  _sectionHeading(
                    context,
                    icon: Icons.group_outlined,
                    title: 'Together',
                  ),
                  for (final row in groupActive) _groupCard(context, row),
                ],
                if (hasFinished)
                  _finishedSection(context, personalDone, groupDone),
                if (_archived.isNotEmpty || _archivedGroups.isNotEmpty)
                  _archivedSection(context),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _trashShortcut(context),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _sectionHeading(
    BuildContext context, {
    required IconData icon,
    required String title,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.gap4, AppSpacing.gap16, AppSpacing.gap4, AppSpacing.gap8),
      child: Row(
        children: [
          Icon(icon,
              size: AppSpacing.iconSm, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _personalCard(BuildContext context, ActivePersonalReading row) {
    final pinned = _pinnedReadingId == row.pinKey;
    return _PlanCardShell(
      pinned: pinned,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitleRow(
            context,
            title: row.plan.title,
            subtitle: row.plan.description,
            state: row.state,
          ),
          if (pinned) _primaryOnHomeTag(context),
          _progressBlock(context, row.status),
          const SizedBox(height: 12),
          CatchUpStatusRow(
            status: row.status,
            onTrackLabel: "You're on track",
            onTap: () => _continuePlan(row),
          ),
          const SizedBox(height: AppSpacing.gap12),
          Row(
            children: [
              Expanded(
                child: _primaryAction(
                  context,
                  icon: Icons.chevron_right,
                  label: 'Continue',
                  onTap: () => _continuePlan(row),
                ),
              ),
              const SizedBox(width: AppSpacing.gap8),
              _pinButton(
                context,
                pinned: pinned,
                onTap: () {
                  _togglePin(row.pinKey);
                },
              ),
              const SizedBox(width: AppSpacing.gap8),
              _moreMenu(
                context,
                items: [
                  (
                    Icons.speed_outlined,
                    'Adjust pace',
                    () => _adjustPersonalPace(row),
                  ),
                  (Icons.edit_outlined, 'Edit plan', () => _editPlan(row)),
                  if (row.state == PlanLifecycle.wrapup)
                    (
                      Icons.task_alt_outlined,
                      'Finish plan',
                      () => _finishPlan(row),
                    ),
                  (
                    Icons.archive_outlined,
                    'Archive plan',
                    () => _archivePlan(row),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _groupCard(BuildContext context, ActiveGroupReading row) {
    final pinned = _pinnedReadingId == row.pinKey;
    final colorScheme = Theme.of(context).colorScheme;
    final members = row.group.memberCount;
    return _PlanCardShell(
      pinned: pinned,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitleRow(
            context,
            title: row.group.name,
            subtitle:
                'Reading together · $members member${members == 1 ? '' : 's'}',
            state: row.state,
          ),
          if (pinned) _primaryOnHomeTag(context),
          if (row.readers.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.gap12),
            Row(
              children: [
                MemberPresenceStack(members: row.readers, size: 26, max: 4),
                const SizedBox(width: AppSpacing.gap12),
                Expanded(
                  child: Text(
                    _groupPresenceText(row.readers),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ],
          _progressBlock(context, row.status),
          const SizedBox(height: 12),
          CatchUpStatusRow(
            status: row.status,
            onTrackLabel:
                row.ownPace ? "You're on track" : 'In step with your group',
            onTap: () => _reviewGroup(row),
          ),
          const SizedBox(height: AppSpacing.gap12),
          Row(
            children: [
              Expanded(
                child: _primaryAction(
                  context,
                  icon: Icons.chevron_right,
                  label: 'Continue',
                  onTap: () => _reviewGroup(row),
                ),
              ),
              const SizedBox(width: AppSpacing.gap8),
              _pinButton(
                context,
                pinned: pinned,
                onTap: () {
                  _togglePin(row.pinKey);
                },
              ),
              const SizedBox(width: AppSpacing.gap8),
              _moreMenu(
                context,
                items: [
                  (
                    Icons.speed_outlined,
                    'Adjust pace',
                    () => _adjustSharedPace(row),
                  ),
                  if (row.state == PlanLifecycle.wrapup)
                    (
                      Icons.task_alt_outlined,
                      'Finish plan',
                      () => _finishGroup(row),
                    ),
                  (
                    Icons.settings_outlined,
                    'Manage members',
                    () => _manageGroup(row),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardTitleRow(
    BuildContext context, {
    required String title,
    required String subtitle,
    required PlanLifecycle state,
  }) {
    final theme = Theme.of(context);
    final badge = _stateBadge(context, state);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.gap4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: AppSpacing.gap12),
          badge,
        ],
      ],
    );
  }

  Widget _primaryOnHomeTag(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.gap8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.push_pin,
              size: AppSpacing.iconSm, color: colorScheme.primary),
          const SizedBox(width: AppSpacing.gap4),
          Text(
            'Primary on Home',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.primary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _progressBlock(BuildContext context, CatchUpStatus status) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final total = status.total;
    final done = status.doneCount;
    final pct = total > 0 ? done / total : 0.0;
    return Column(
      children: [
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(pct * 100).round()}% complete',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '$done of $total read',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.rSmall),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 7,
            backgroundColor: colorScheme.surfaceContainerHighest,
            color: colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _finishedSection(
    BuildContext context,
    List<ActivePersonalReading> personalDone,
    List<ActiveGroupReading> groupDone,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gap4, AppSpacing.gap32,
              AppSpacing.gap4, AppSpacing.gap8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Finished',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'done · progress kept',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        // A fully-read plan keeps its look; one the reader Finished early
        // says how much was read and can be restored (ADR-0010).
        for (final row in personalDone)
          _finishedRow(
            context,
            icon: Icons.check_circle,
            title: row.plan.title,
            subtitle: row.finished && row.state != PlanLifecycle.complete
                ? 'Finished · ${row.status.doneCount} of ${row.status.total} read'
                : 'All ${row.status.total} readings complete',
            onReview: () => _continuePlan(row),
            onRestore: row.finished ? () => _unfinishPlan(row) : null,
          ),
        for (final row in groupDone)
          _finishedRow(
            context,
            icon: Icons.group,
            title: row.group.name,
            subtitle: row.finished && row.state != PlanLifecycle.complete
                ? 'Finished · ${row.status.doneCount} of ${row.status.total} read'
                : 'Finished together · All ${row.status.total} readings complete',
            onReview: () => _reviewGroup(row),
            onRestore: row.finished ? () => _unfinishGroup(row) : null,
          ),
      ],
    );
  }

  Widget _finishedRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onReview,
    VoidCallback? onRestore,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.gap12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppSpacing.rInset),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.of(context).primarySoft,
              borderRadius: BorderRadius.circular(AppSpacing.rChip),
            ),
            child: Icon(icon, size: 20, color: colorScheme.primary),
          ),
          const SizedBox(width: AppSpacing.gap12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onReview, child: const Text('Review')),
          if (onRestore != null)
            IconButton(
              onPressed: onRestore,
              icon: const Icon(Icons.restore),
              tooltip: 'Restore plan',
              color: colorScheme.primary,
            ),
        ],
      ),
    );
  }

  Widget _archivedSection(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [
      for (final row in _archived) _archivedRow(context, row),
      for (final group in _archivedGroups) _archivedGroupRow(context, group),
    ];
    // Keep a long archive from pushing the rest of Path far down the page.
    const collapsedCount = 2;
    final collapsible = rows.length > collapsedCount;
    final shown =
        collapsible && !_showAllArchived ? rows.take(collapsedCount) : rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gap4, AppSpacing.gap32,
              AppSpacing.gap4, AppSpacing.gap8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Archived',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'shelved · progress kept',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        ...shown,
        if (collapsible)
          Center(
            child: TextButton(
              onPressed: () =>
                  setState(() => _showAllArchived = !_showAllArchived),
              child: Text(
                _showAllArchived ? 'Show less' : 'Show all ${rows.length}',
              ),
            ),
          ),
      ],
    );
  }

  /// Archive row for an archived group (#776): owned groups return with
  /// unarchive (owner) — participation returns with unarchive (member).
  Widget _archivedGroupRow(BuildContext context, Group group) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final uid = widget.auth.currentUser?.uid;
    final isOwner = uid != null && uid == group.ownerUid;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.gap12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppSpacing.rInset),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppSpacing.rChip),
            ),
            child: Icon(
              Icons.group_outlined,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.gap12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 1),
                Text(
                  isOwner ? 'Group archived' : 'Your participation archived',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _unarchiveGroup(group),
            icon: const Icon(Icons.restore),
            tooltip: 'Unarchive group',
            color: colorScheme.primary,
          ),
          if (isOwner)
            IconButton(
              onPressed: () => _confirmTrashGroup(group),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete group',
              color: colorScheme.error.withValues(alpha: 0.7),
            ),
        ],
      ),
    );
  }

  Widget _archivedRow(BuildContext context, ActivePersonalReading row) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.gap12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppSpacing.rInset),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppSpacing.rChip),
            ),
            child: Icon(
              Icons.archive_outlined,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.gap12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.plan.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 1),
                Text(
                  'All ${row.status.total} readings kept',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _restorePlan(row),
            icon: const Icon(Icons.restore),
            tooltip: 'Unarchive and continue',
            color: colorScheme.primary,
          ),
          IconButton(
            onPressed: () => _confirmTrashPlan(row),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete plan',
            color: colorScheme.error.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }

  Widget _enrollButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: _enroll,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Enroll in a new plan'),
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          // From the theme so the label keeps the app font; a bare TextStyle
          // here replaces the theme's and falls back to the system font.
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.rInset),
          ),
        ),
      ),
    );
  }

  /// Quiet link to the Recently Deleted hub (#776) at the foot of the list,
  /// with a hint of how much is waiting in the trash.
  Widget _trashShortcut(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: TextButton.icon(
        onPressed: _openTrash,
        icon: const Icon(Icons.delete_outline, size: 18),
        label: Text(
          _trashedCount > 0
              ? 'Recently Deleted · $_trashedCount waiting'
              : 'Recently Deleted',
        ),
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 56,
            color: colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No active plans yet',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Start a plan to give your reading a gentle rhythm.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          _enrollButton(context),
          const SizedBox(height: AppSpacing.gap8),
          _trashShortcut(context),
          if (_archived.isNotEmpty || _archivedGroups.isNotEmpty) ...[
            const SizedBox(height: 8),
            _archivedSection(context),
          ],
        ],
      ),
    );
  }

  // ---- Small action widgets ----------------------------------------------

  Widget _primaryAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 46,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 14,
              ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.rInset),
          ),
        ),
      ),
    );
  }

  Widget _pinButton(
    BuildContext context, {
    required bool pinned,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return _squareButton(
      onTap: onTap,
      tooltip: pinned ? 'Unpin from Home' : 'Pin as Home primary',
      background: pinned
          ? AppColors.of(context).primarySoft
          : colorScheme.surfaceContainerHighest,
      borderColor: pinned
          ? AppColors.of(context).primaryLine
          : AppColors.of(context).border,
      child: Icon(
        pinned ? Icons.push_pin : Icons.push_pin_outlined,
        size: 18,
        color: pinned ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
    );
  }

  /// Overflow for the occasional per-card actions, so the primary button
  /// keeps its width at large text sizes.
  Widget _moreMenu(
    BuildContext context, {
    required List<(IconData, String, VoidCallback)> items,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<VoidCallback>(
      tooltip: 'More actions',
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        for (final (icon, label, action) in items)
          PopupMenuItem<VoidCallback>(
            value: action,
            child: Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Text(label),
              ],
            ),
          ),
      ],
      child: SizedBox(
        width: 46,
        height: 46,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppSpacing.rInset),
            border: Border.all(color: AppColors.of(context).border),
          ),
          child: Icon(
            Icons.more_horiz,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _squareButton({
    required VoidCallback onTap,
    required Color background,
    required Color borderColor,
    required Widget child,
    String? tooltip,
  }) {
    final button = SizedBox(
      width: 46,
      height: 46,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.rInset),
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(child: child),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }

  /// Only states the catch-up row beneath does not already say get a badge —
  /// "behind" and "on track" are left to that row.
  Widget? _stateBadge(BuildContext context, PlanLifecycle state) {
    final colorScheme = Theme.of(context).colorScheme;
    late final String label;
    late final Color color;
    switch (state) {
      case PlanLifecycle.due:
        label = 'Due today';
        color = colorScheme.primary;
        break;
      case PlanLifecycle.wrapup:
        label = 'Ended';
        color = colorScheme.tertiary;
        break;
      case PlanLifecycle.behind:
      case PlanLifecycle.complete:
      case PlanLifecycle.ontrack:
        return null;
    }
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gap8, vertical: AppSpacing.gap4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.rPill),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              letterSpacing: 0.2,
            ),
      ),
    );
  }

  String _groupPresenceText(List<GroupMemberProgressData> readers) {
    if (readers.isEmpty) return 'No one has read yet';
    final names = readers.take(2).map((r) => r.name.split(' ').first).toList();
    final more = readers.length - names.length;
    final suffix = more > 0 ? ' & $more other${more > 1 ? 's' : ''}' : '';
    return '${names.join(', ')}$suffix read';
  }
}

/// Rounded card chrome shared by personal and Shared plan cards, highlighted
/// when the plan is pinned as the Home primary.
class _PlanCardShell extends StatelessWidget {
  final bool pinned;
  final Widget child;
  const _PlanCardShell({required this.pinned, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.gap12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(
          color: pinned
              ? AppColors.of(context).primaryLine
              : AppColors.of(context).border,
        ),
      ),
      child: child,
    );
  }
}
