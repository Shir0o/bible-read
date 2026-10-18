import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../services/active_reading_aggregator.dart';
import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../services/reading_plan_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_styles.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/skeletons/list_rows_skeleton.dart';
import '../widgets/sub_header.dart';

/// The Archive (#776), opened from the Path tab: shelved personal plans and
/// archived groups, each with unarchive and delete (to Recently Deleted).
class ArchivedPage extends StatefulWidget {
  final FirebaseAuth auth;
  final GroupService groupService;
  final ReadingPlanService readingPlanService;
  final ActiveReadingAggregator aggregator;
  final VibrationService vibrationService;
  final DateTime Function() dateProvider;

  const ArchivedPage({
    super.key,
    required this.auth,
    required this.groupService,
    required this.readingPlanService,
    required this.aggregator,
    this.vibrationService = const VibrationService(),
    required this.dateProvider,
  });

  @override
  State<ArchivedPage> createState() => _ArchivedPageState();
}

class _ArchivedPageState extends State<ArchivedPage> {
  bool _loading = true;
  List<ActivePersonalReading> _archived = [];
  List<Group> _archivedGroups = [];

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
    try {
      final archived = await widget.aggregator
          .fetchArchivedPlans(uid, today: widget.dateProvider());
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
      if (mounted) {
        setState(() {
          _archived = archived;
          _archivedGroups = archivedGroups;
          _loading = false;
        });
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) setState(() => _loading = false);
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
            style: AppButtonStyles.destructiveText(context),
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
            style: AppButtonStyles.destructiveText(context),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final empty = _archived.isEmpty && _archivedGroups.isEmpty;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SubHeader(
              title: 'Archived',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: SkeletonLoader(
                loading: _loading,
                skeleton: const ListRowsSkeleton(),
                child: empty
                    ? _emptyState(context)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.gap16,
                            AppSpacing.gap8,
                            AppSpacing.gap16,
                            AppSpacing.gap24),
                        children: [
                          for (final row in _archived)
                            _archivedRow(context, row),
                          for (final group in _archivedGroups)
                            _archivedGroupRow(context, group),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.archive_outlined,
            size: 56,
            color: colorScheme.outline,
          ),
          const SizedBox(height: AppSpacing.gap16),
          Text(
            'Nothing archived',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.gap6),
          Text(
            'Plans you shelve wait here with their progress kept.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gap16, vertical: AppSpacing.gap12),
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
                const SizedBox(height: AppSpacing.gap2),
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
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gap16, vertical: AppSpacing.gap12),
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
                const SizedBox(height: AppSpacing.gap2),
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
}
