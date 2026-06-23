import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

import '../models/group.dart';
import '../models/group_member_progress.dart';
import '../models/group_schedule.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';
import '../services/catch_up_engine.dart';
import '../services/error_logger.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../services/reading_plan_service.dart';
import '../services/user_preferences_service.dart';
import '../services/vibration_service.dart';
import '../widgets/catch_up_status_row.dart';
import '../widgets/member_presence_stack.dart';
import '../widgets/new_plan_picker_sheet.dart';
import 'create_group_page.dart';
import 'create_plan_page.dart';
import 'full_schedule_page.dart';
import 'group_detail_page.dart';
import 'group_members_page.dart';
import 'plan_detail_page.dart';

/// "My Reading Plans" — a single hub listing *everything* the user is reading:
/// their personal plans ("On your own") and the group plans of circles they
/// belong to ("Together"), each as a rich card tagged with its lifecycle state,
/// with per-card actions (continue, pin as Home primary, edit, leave/manage).
/// Completed plans collapse into a "Finished" list. Reached from Home's
/// "All plans" / "Manage all N plans" affordances.
class AllPlansPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final GroupService groupService;
  final ReadingPlanService readingPlanService;
  final UserPreferencesService userPreferencesService;
  final FriendService friendService;
  final VibrationService vibrationService;
  final DateTime Function() dateProvider;

  const AllPlansPage({
    super.key,
    required this.firestore,
    required this.auth,
    required this.groupService,
    required this.readingPlanService,
    required this.userPreferencesService,
    required this.friendService,
    required this.vibrationService,
    required this.dateProvider,
  });

  @override
  State<AllPlansPage> createState() => _AllPlansPageState();
}

class _PersonalRow {
  final ReadingPlan plan;
  final UserPlanProgress progress;
  final CatchUpStatus status;
  final PlanLifecycle state;
  const _PersonalRow(this.plan, this.progress, this.status, this.state);

  String get pinKey => 'plan:${plan.id}';
}

class _GroupRow {
  final Group group;
  final List<GroupSchedule> schedule;
  final List<GroupMemberProgressData> readers;
  final CatchUpStatus status;
  final PlanLifecycle state;
  const _GroupRow(
      this.group, this.schedule, this.readers, this.status, this.state);

  String get pinKey => 'group:${group.id}';
}

class _AllPlansPageState extends State<AllPlansPage> {
  bool _loading = true;
  List<_PersonalRow> _personal = [];
  List<_GroupRow> _groups = [];
  String? _pinnedReadingId;

  /// Id of the personal plan whose inline "leave" tap is awaiting confirmation.
  String? _confirmingLeaveId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
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

      // Personal plans.
      final progresses = await widget.readingPlanService
          .getActivePlans(uid)
          .first
          .timeout(const Duration(seconds: 5),
              onTimeout: () => const <UserPlanProgress>[]);
      final personal = <_PersonalRow>[];
      for (final progress in progresses) {
        final plan = await widget.readingPlanService
            .getPlanById(progress.planId, userId: uid);
        if (plan == null) continue;
        final status =
            CatchUpEngine.forPersonalPlan(plan, progress, today: today);
        personal.add(
            _PersonalRow(plan, progress, status, status.lifecycleAt(today)));
      }

      // Group readings (the user's groups).
      final groups = await widget.groupService.groupsForUser(uid).first.timeout(
          const Duration(seconds: 5),
          onTimeout: () => const <Group>[]);
      final groupRows = <_GroupRow>[];
      for (final group in groups) {
        final results = await Future.wait([
          widget.groupService.schedule(group.id).first.timeout(
              const Duration(seconds: 3),
              onTimeout: () => const <GroupSchedule>[]),
          widget.groupService.userProgressForGroup(group.id, uid).first.timeout(
              const Duration(seconds: 3),
              onTimeout: () => const <String, int>{}),
          widget.groupService
              .memberDailyCompletion(group.id, date: today)
              .first
              .timeout(const Duration(seconds: 3),
                  onTimeout: () => const <GroupMemberProgressData>[]),
        ]);
        final schedule = results[0] as List<GroupSchedule>;
        final progressMap = results[1] as Map<String, int>;
        final members = results[2] as List<GroupMemberProgressData>;
        final completed = progressMap.entries
            .where((e) => e.value > 0)
            .map((e) => e.key)
            .toSet();
        final status =
            CatchUpEngine.forGroupSchedule(schedule, completed, today: today);
        final readers =
            members.where((m) => m.completion >= 1.0).toList(growable: false);
        groupRows.add(_GroupRow(
            group, schedule, readers, status, status.lifecycleAt(today)));
      }

      if (mounted) {
        setState(() {
          _personal = personal;
          _groups = groupRows;
          _pinnedReadingId = pinned;
          _loading = false;
        });
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) setState(() => _loading = false);
    }
  }

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

  Future<void> _editPlan(_PersonalRow row) async {
    widget.vibrationService.lightImpact();
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CreatePlanPage(
        firestore: widget.firestore,
        auth: widget.auth,
        vibrationService: widget.vibrationService,
        editingPlan: row.plan,
        editingProgress: row.progress,
      ),
    ));
    if (changed == true && mounted) await _load();
  }

  Future<void> _leavePlan(_PersonalRow row) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    widget.vibrationService.lightImpact();
    try {
      await widget.readingPlanService.setPlanArchived(uid, row.plan.id, true);
      if (!mounted) return;
      // Clear the inline confirmation only once the archive has succeeded, so a
      // failed write leaves the card in its "tap to confirm" state.
      setState(() => _confirmingLeaveId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Left "${row.plan.title}"')),
      );
      await _load();
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  void _continuePlan(_PersonalRow row) {
    widget.vibrationService.lightImpact();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlanDetailPage(
        plan: row.plan,
        firestore: widget.firestore,
        auth: widget.auth,
        initialProgress: row.progress,
        vibrationService: widget.vibrationService,
      ),
    ));
  }

  void _openGroup(_GroupRow row) {
    widget.vibrationService.lightImpact();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupDetailPage(
        group: row.group,
        groupService: widget.groupService,
        auth: widget.auth,
      ),
    ));
  }

  void _manageGroup(_GroupRow row) {
    widget.vibrationService.lightImpact();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupMembersPage(
        group: row.group,
        groupService: widget.groupService,
        friendService: widget.friendService,
        auth: widget.auth,
        vibrationService: widget.vibrationService,
      ),
    ));
  }

  void _reviewGroup(_GroupRow row) {
    widget.vibrationService.lightImpact();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FullSchedulePage(
        group: row.group,
        groupService: widget.groupService,
        auth: widget.auth,
        vibrationService: widget.vibrationService,
        initialSchedule: row.schedule,
        isMember: true,
      ),
    ));
  }

  Future<void> _enroll() async {
    widget.vibrationService.lightImpact();
    final kind = await showNewPlanPicker(context);
    if (kind == null || !mounted) return;

    // Both create pages replace themselves with a detail page on success
    // (pushReplacement), so the push future can't reliably report whether a
    // plan was created. Reload on return so a newly created plan/group always
    // shows in the hub; the occasional wasted reload on cancel is cheap.
    switch (kind) {
      case NewPlanKind.personal:
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CreatePlanPage(
            firestore: widget.firestore,
            auth: widget.auth,
            vibrationService: widget.vibrationService,
          ),
        ));
      case NewPlanKind.group:
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CreateGroupPage(
            groupService: widget.groupService,
            auth: widget.auth,
            vibrationService: widget.vibrationService,
          ),
        ));
    }
    if (mounted) await _load();
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final personalActive =
        _personal.where((r) => r.state != PlanLifecycle.complete).toList();
    final personalDone =
        _personal.where((r) => r.state == PlanLifecycle.complete).toList();
    final groupActive =
        _groups.where((r) => r.state != PlanLifecycle.complete).toList();
    final groupDone =
        _groups.where((r) => r.state == PlanLifecycle.complete).toList();
    final totalActive = personalActive.length + groupActive.length;
    final hasFinished = personalDone.isNotEmpty || groupDone.isNotEmpty;
    final nothing = totalActive == 0 && !hasFinished;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reading Plans'),
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      backgroundColor: colorScheme.surface,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: nothing
                  ? _emptyState(context)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                      children: [
                        _headerStrip(context, totalActive),
                        if (personalActive.isNotEmpty) ...[
                          _sectionHeading(context,
                              icon: Icons.explore_outlined,
                              title: 'On your own',
                              count: personalActive.length,
                              countLabel: 'personal'),
                          for (final row in personalActive)
                            _personalCard(context, row),
                        ],
                        if (groupActive.isNotEmpty) ...[
                          SizedBox(height: personalActive.isNotEmpty ? 22 : 0),
                          _sectionHeading(context,
                              icon: Icons.group_outlined,
                              title: 'Together',
                              count: groupActive.length,
                              countLabel: 'group'),
                          for (final row in groupActive)
                            _groupCard(context, row),
                        ],
                        if (hasFinished)
                          _finishedSection(context, personalDone, groupDone),
                        const SizedBox(height: 22),
                        _enrollButton(context),
                      ],
                    ),
            ),
    );
  }

  Widget _headerStrip(BuildContext context, int totalActive) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "Everything you're reading — on your own and together",
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.of(context).primarySoft,
              borderRadius: BorderRadius.circular(99),
              border:
                  Border.all(color: AppColors.of(context).primaryLine),
            ),
            child: Text(
              '$totalActive ongoing',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeading(
    BuildContext context, {
    required IconData icon,
    required String title,
    required int count,
    required String countLabel,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.of(context).primarySoft,
              borderRadius: BorderRadius.circular(99),
              border:
                  Border.all(color: AppColors.of(context).primaryLine),
            ),
            child: Text(
              '$count $countLabel',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _personalCard(BuildContext context, _PersonalRow row) {
    final pinned = _pinnedReadingId == row.pinKey;
    final confirming = _confirmingLeaveId == row.plan.id;
    return _PlanCardShell(
      pinned: pinned,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitleRow(context,
              title: row.plan.title,
              subtitle: row.plan.description,
              state: row.state,
              missed: row.status.missedCount),
          if (pinned) _primaryOnHomeTag(context),
          _progressBlock(context, row.status),
          const SizedBox(height: 12),
          CatchUpStatusRow(
            status: row.status,
            onTrackLabel: "You're on track",
            onTap: () => _continuePlan(row),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _primaryAction(context,
                    icon: Icons.chevron_right,
                    label: 'Continue',
                    onTap: () => _continuePlan(row)),
              ),
              const SizedBox(width: 9),
              _pinButton(context, pinned: pinned, onTap: () {
                _togglePin(row.pinKey);
              }),
              const SizedBox(width: 9),
              _iconAction(context,
                  icon: Icons.edit_outlined, onTap: () => _editPlan(row)),
              const SizedBox(width: 9),
              _leaveButton(context, confirming: confirming, onTap: () {
                if (confirming) {
                  _leavePlan(row);
                } else {
                  setState(() => _confirmingLeaveId = row.plan.id);
                }
              }),
            ],
          ),
          if (confirming)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: GestureDetector(
                onTap: () => setState(() => _confirmingLeaveId = null),
                child: Text(
                  'Tap the check to leave "${row.plan.title}", or cancel',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _groupCard(BuildContext context, _GroupRow row) {
    final pinned = _pinnedReadingId == row.pinKey;
    final colorScheme = Theme.of(context).colorScheme;
    final members = row.group.memberCount;
    return _PlanCardShell(
      pinned: pinned,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitleRow(context,
              title: row.group.name,
              subtitle:
                  'Reading together · $members member${members == 1 ? '' : 's'}',
              state: row.state,
              missed: row.status.missedCount),
          if (pinned) _primaryOnHomeTag(context),
          if (row.readers.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                MemberPresenceStack(members: row.readers, size: 26, max: 4),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _groupPresenceText(row.readers),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
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
            onTrackLabel: 'In step with your community',
            onTap: () => _reviewGroup(row),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _primaryAction(context,
                    icon: Icons.chevron_right,
                    label: 'Read together',
                    onTap: () => _openGroup(row)),
              ),
              const SizedBox(width: 9),
              _pinButton(context, pinned: pinned, onTap: () {
                _togglePin(row.pinKey);
              }),
              const SizedBox(width: 9),
              _iconAction(context,
                  icon: Icons.settings_outlined,
                  onTap: () => _manageGroup(row)),
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
    required int missed,
  }) {
    final theme = Theme.of(context);
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
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
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
        const SizedBox(width: 10),
        _stateBadge(context, state, missed),
      ],
    );
  }

  Widget _primaryOnHomeTag(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.push_pin, size: 13, color: colorScheme.primary),
          const SizedBox(width: 5),
          Text(
            'Primary on Home',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
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
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
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
    List<_PersonalRow> personalDone,
    List<_GroupRow> groupDone,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 28, 4, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Finished',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'completed in full',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        for (final row in personalDone)
          _finishedRow(context,
              icon: Icons.check_circle,
              title: row.plan.title,
              subtitle: 'All ${row.status.total} readings complete',
              onReview: () => _continuePlan(row)),
        for (final row in groupDone)
          _finishedRow(context,
              icon: Icons.group,
              title: row.group.name,
              subtitle:
                  'Finished together · All ${row.status.total} readings complete',
              onReview: () => _reviewGroup(row)),
      ],
    );
  }

  Widget _finishedRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onReview,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
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
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: colorScheme.primary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onReview, child: const Text('Review')),
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
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        const SizedBox(height: 100),
        Icon(Icons.menu_book_outlined,
            size: 56,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
        const SizedBox(height: 16),
        Text(
          'No active plans yet',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w500),
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
      ],
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
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _pinButton(BuildContext context,
      {required bool pinned, required VoidCallback onTap}) {
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

  Widget _iconAction(BuildContext context,
      {required IconData icon, required VoidCallback onTap}) {
    final colorScheme = Theme.of(context).colorScheme;
    return _squareButton(
      onTap: onTap,
      background: colorScheme.surfaceContainerHighest,
      borderColor: AppColors.of(context).border,
      child: Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
    );
  }

  Widget _leaveButton(BuildContext context,
      {required bool confirming, required VoidCallback onTap}) {
    final colorScheme = Theme.of(context).colorScheme;
    return _squareButton(
      onTap: onTap,
      tooltip: 'Leave plan',
      background: confirming
          ? AppColors.of(context).accentSoft
          : colorScheme.surfaceContainerHighest,
      borderColor: confirming
          ? colorScheme.tertiary.withValues(alpha: 0.5)
          : AppColors.of(context).border,
      child: Icon(
        confirming ? Icons.check : Icons.close,
        size: 18,
        color: confirming ? colorScheme.tertiary : colorScheme.onSurfaceVariant,
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
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Center(child: child)),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }

  Widget _stateBadge(BuildContext context, PlanLifecycle state, int missed) {
    final colorScheme = Theme.of(context).colorScheme;
    late final String label;
    late final Color color;
    switch (state) {
      case PlanLifecycle.due:
        label = 'Due today';
        color = colorScheme.primary;
        break;
      case PlanLifecycle.behind:
        label = '$missed behind';
        color = colorScheme.tertiary;
        break;
      case PlanLifecycle.wrapup:
        label = 'Ended · finish';
        color = colorScheme.tertiary;
        break;
      case PlanLifecycle.complete:
        label = 'Finished';
        color = colorScheme.primary;
        break;
      case PlanLifecycle.ontrack:
        label = 'On track';
        color = colorScheme.onSurfaceVariant;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
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

/// Rounded card chrome shared by personal and group plan cards, highlighted
/// when the plan is pinned as the Home primary.
class _PlanCardShell extends StatelessWidget {
  final bool pinned;
  final Widget child;
  const _PlanCardShell({required this.pinned, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
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
