import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

import '../../models/group_member_progress.dart';
import '../../services/active_reading_aggregator.dart';
import '../../services/catch_up_engine.dart';
import '../../services/error_logger.dart';
import '../../services/nudge_service.dart';
import '../../services/group_service.dart';
import '../../services/reading_plan_service.dart';
import '../../services/user_preferences_service.dart';
import '../../services/vibration_service.dart';
import '../catch_up_status_row.dart';
import '../common_styles.dart';
import '../member_presence_stack.dart';
import '../../pages/adjust_pace_page.dart';
import '../../pages/create_plan_page.dart';
import '../../pages/group_members_page.dart';
import '../../pages/plan_detail_page.dart';
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
  List<ActiveGroupReading> _groups = [];
  String? _pinnedReadingId;

  late final ActiveReadingAggregator _aggregator;

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

      if (mounted) {
        setState(() {
          _personal = snapshot.personalPlans;
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

  /// Adjust pace on a Shared plan: owner adjusts the Group schedule for everyone.
  Future<void> _adjustSharedPace(ActiveGroupReading row) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null || !_isOwner(row)) return;
    final today = widget.dateProvider();
    final applied = await adjustSharedPace(
      context,
      firestore: widget.firestore,
      groupService: widget.groupService,
      groupName: row.group.name,
      uid: uid,
      groupId: row.group.id,
      schedule: row.schedule,
      completedDateIds: row.completedDateIds,
      daysBehind: row.status.missedCount,
      today: today,
      vibrationService: widget.vibrationService,
    );
    if (applied && mounted) await _load();
  }

  /// Confirms deleting a personal plan.
  Future<void> _confirmDeletePersonalPlan(ActivePersonalReading row) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      builder: (context) => AlertDialog(
        title: Text('Delete “${row.plan.title}”?'),
        content: const Text(
          'This removes the plan from your reading list. Chapters you '
          'already read stay in your history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: AppButtonStyles.destructiveText(context),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    widget.vibrationService.lightImpact();
    try {
      await widget.readingPlanService.leavePlan(uid, row.plan.id);
      if (mounted) await _load();
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        _showSnack('Failed to delete "${row.plan.title}". Please try again.');
      }
    }
  }

  /// Confirms deleting (for owner) or leaving (for member) a shared group plan.
  Future<void> _confirmRemoveGroup(ActiveGroupReading row) async {
    final owner = _isOwner(row);
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      builder: (context) => AlertDialog(
        title: Text(owner
            ? 'Delete “${row.group.name}”?'
            : 'Leave “${row.group.name}”?'),
        content: Text(
          owner
              ? 'The plan ends for everyone and is removed from their reading list. '
                  'Chapters already read stay in everyone’s reading history.'
              : 'The plan carries on for everyone else.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: AppButtonStyles.destructiveText(context),
            child: Text(owner ? 'Delete' : 'Leave'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    widget.vibrationService.lightImpact();
    try {
      if (owner) {
        await widget.groupService.deleteGroup(
          groupId: row.group.id,
          ownerUid: uid,
        );
      } else {
        await widget.groupService.leaveGroup(
          groupId: row.group.id,
          uid: uid,
        );
      }
      if (mounted) await _load();
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        _showSnack(
            'Failed to ${owner ? 'delete' : 'leave'} "${row.group.name}". Please try again.');
      }
    }
  }

  /// Owner or member, decided as on the Edit group page.
  bool _isOwner(ActiveGroupReading row) =>
      widget.auth.currentUser?.uid == row.group.ownerUid;

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
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
    final personalActive =
        _personal.where((r) => r.state != PlanLifecycle.complete).toList();
    final groupActive =
        _groups.where((r) => r.state != PlanLifecycle.complete).toList();
    final totalActive = personalActive.length + groupActive.length;

    if (!_loading && totalActive == 0) return _emptyState(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.hPadding, AppSpacing.gap4, AppSpacing.hPadding, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonLoader(
            loading: _loading,
            minTime: const Duration(milliseconds: 1000),
            skeleton: const PlansHubSkeleton(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.gap16),
                if (personalActive.isNotEmpty) ...[
                  _sectionHeading(context, title: 'On your own'),
                  for (final row in personalActive) _personalCard(context, row),
                ],
                if (groupActive.isNotEmpty) ...[
                  SizedBox(
                      height: personalActive.isNotEmpty ? AppSpacing.gap16 : 0),
                  _sectionHeading(context, title: 'Together'),
                  for (final row in groupActive) _groupCard(context, row),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.gap20),
        ],
      ),
    );
  }

  /// Matches Today's "Today’s reading" label: a quiet titleSmall in a
  /// 44px row.
  Widget _sectionHeading(BuildContext context, {required String title}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gap4),
      child: SizedBox(
        height: 44,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
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
          const SizedBox(height: AppSpacing.gap12),
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
                ],
                destructive: (
                  Icons.delete_outline,
                  'Delete plan',
                  () => _confirmDeletePersonalPlan(row),
                ),
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
          const SizedBox(height: AppSpacing.gap12),
          CatchUpStatusRow(
            status: row.status,
            onTrackLabel: 'In step with your group',
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
                  if (_isOwner(row))
                    (
                      Icons.speed_outlined,
                      'Adjust pace',
                      () => _adjustSharedPace(row),
                    ),
                  (
                    Icons.settings_outlined,
                    'Members and invites',
                    () => _manageGroup(row),
                  ),
                ],
                destructive: (
                  Icons.delete_outline,
                  _isOwner(row) ? 'Delete plan' : 'Leave plan',
                  () => _confirmRemoveGroup(row),
                ),
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
        const SizedBox(height: AppSpacing.gap16),
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
        const SizedBox(height: AppSpacing.gap8),
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

  Widget _enrollButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: _enroll,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Enroll in a new plan'),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppSpacing.gap24, 48, AppSpacing.gap24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 56,
            color: colorScheme.outline,
          ),
          const SizedBox(height: AppSpacing.gap16),
          Text(
            'No active plans yet',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.gap6),
          Text(
            'Start a plan to give your reading a gentle rhythm.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.gap24),
          _enrollButton(context),
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
    return SizedBox(
      height: 46,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
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
    (IconData, String, VoidCallback)? destructive,
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
                const SizedBox(width: AppSpacing.gap12),
                Flexible(child: Text(label)),
              ],
            ),
          ),
        if (destructive case (final icon, final label, final action)) ...[
          const PopupMenuDivider(),
          PopupMenuItem<VoidCallback>(
            value: action,
            child: Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.error),
                const SizedBox(width: AppSpacing.gap12),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(color: colorScheme.error),
                  ),
                ),
              ],
            ),
          ),
        ],
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
      padding: const EdgeInsets.all(AppSpacing.gap20),
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
