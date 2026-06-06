import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_schedule.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';
import '../services/catch_up_engine.dart';
import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../services/reading_plan_service.dart';
import '../services/vibration_service.dart';
import 'full_schedule_page.dart';
import 'plan_detail_page.dart';

/// A single combined hub listing *both* the user's personal reading plans and
/// their group readings, each tagged with its lifecycle state. Reached from
/// Home's "Manage all N plans" / "All plans" affordances.
class AllPlansPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final GroupService groupService;
  final ReadingPlanService readingPlanService;
  final VibrationService vibrationService;
  final DateTime Function() dateProvider;

  const AllPlansPage({
    super.key,
    required this.firestore,
    required this.auth,
    required this.groupService,
    required this.readingPlanService,
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
}

class _GroupRow {
  final Group group;
  final List<GroupSchedule> schedule;
  final CatchUpStatus status;
  final PlanLifecycle state;
  const _GroupRow(this.group, this.schedule, this.status, this.state);
}

class _AllPlansPageState extends State<AllPlansPage> {
  bool _loading = true;
  List<_PersonalRow> _personal = [];
  List<_GroupRow> _groups = [];

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

      // Group readings.
      final groups = await widget.groupService
          .groupsForUser(uid)
          .first
          .timeout(const Duration(seconds: 5), onTimeout: () => const <Group>[]);
      final groupRows = <_GroupRow>[];
      for (final group in groups) {
        final results = await Future.wait([
          widget.groupService.schedule(group.id).first.timeout(
              const Duration(seconds: 3),
              onTimeout: () => const <GroupSchedule>[]),
          widget.groupService.userProgressForGroup(group.id, uid).first.timeout(
              const Duration(seconds: 3),
              onTimeout: () => const <String, int>{}),
        ]);
        final schedule = results[0] as List<GroupSchedule>;
        final progressMap = results[1] as Map<String, int>;
        final completed = progressMap.entries
            .where((e) => e.value > 0)
            .map((e) => e.key)
            .toSet();
        final status = CatchUpEngine.forGroupSchedule(schedule, completed,
            today: today);
        groupRows
            .add(_GroupRow(group, schedule, status, status.lifecycleAt(today)));
      }

      if (mounted) {
        setState(() {
          _personal = personal;
          _groups = groupRows;
          _loading = false;
        });
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('All plans'),
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      backgroundColor: colorScheme.surface,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: (_personal.isEmpty && _groups.isEmpty)
                  ? _emptyState(context)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      children: [
                        if (_personal.isNotEmpty) ...[
                          _sectionHeader(
                              context, 'Reading plans', _personal.length),
                          for (final row in _personal)
                            _personalCard(context, row),
                        ],
                        if (_groups.isNotEmpty) ...[
                          _sectionHeader(context, 'Groups', _groups.length),
                          for (final row in _groups) _groupCard(context, row),
                        ],
                      ],
                    ),
            ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.menu_book_outlined,
            size: 56,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'No active plans or groups yet.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title, int count) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),
          Text(
            '$count',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _personalCard(BuildContext context, _PersonalRow row) {
    return _planCard(
      context,
      icon: Icons.explore_outlined,
      title: row.plan.title,
      subtitle: row.plan.description,
      status: row.status,
      state: row.state,
      onTap: () {
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
      },
    );
  }

  Widget _groupCard(BuildContext context, _GroupRow row) {
    return _planCard(
      context,
      icon: Icons.group_outlined,
      title: '${row.group.name} · together',
      subtitle: 'Group reading',
      status: row.status,
      state: row.state,
      onTap: () {
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
      },
    );
  }

  Widget _planCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required CatchUpStatus status,
    required PlanLifecycle state,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final total = status.total;
    final done = status.doneCount;
    final pct = total > 0 ? done / total : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 1,
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
                    _stateBadge(context, state, status.missedCount),
                  ],
                ),
                const SizedBox(height: 14),
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
            ),
          ),
        ),
      ),
    );
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
}
