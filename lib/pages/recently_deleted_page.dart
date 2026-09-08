import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/reading_plan_progress.dart';
import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../services/reading_plan_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/sub_header.dart';

/// One row in the Recently Deleted hub: a soft-deleted personal plan or an
/// owned group, with the days left before its permanent purge (#776).
class _TrashItem {
  final String id;
  final String title;
  final bool isGroup;
  final DateTime deleteAfter;

  const _TrashItem({
    required this.id,
    required this.title,
    required this.isGroup,
    required this.deleteAfter,
  });

  int daysLeft(DateTime now) => deleteAfter.difference(now).inDays.clamp(0, 30);
}

/// The Recently Deleted hub (#776): everything soft-deleted — personal plans
/// and owned groups — with a 30-day countdown per row, restore (back to its
/// pre-deletion state), individual permanent delete, and Empty Trash.
class RecentlyDeletedPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final GroupService groupService;
  final ReadingPlanService readingPlanService;
  final VibrationService vibrationService;
  final DateTime Function() dateProvider;

  const RecentlyDeletedPage({
    super.key,
    required this.firestore,
    required this.auth,
    required this.groupService,
    required this.readingPlanService,
    this.vibrationService = const VibrationService(),
    required this.dateProvider,
  });

  @override
  State<RecentlyDeletedPage> createState() => _RecentlyDeletedPageState();
}

class _RecentlyDeletedPageState extends State<RecentlyDeletedPage> {
  bool _loading = true;
  List<_TrashItem> _items = [];

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
      final items = <_TrashItem>[];

      // Personal plans moved to the trash.
      final progresses =
          await widget.readingPlanService.getDeletedPlans(uid).first.timeout(
                const Duration(seconds: 5),
                onTimeout: () => const <UserPlanProgress>[],
              );
      for (final progress in progresses) {
        if (progress.deleteAfter == null) continue;
        final plan = await widget.readingPlanService.getPlanById(
          progress.planId,
          userId: uid,
        );
        items.add(
          _TrashItem(
            id: progress.planId,
            title: plan?.title ?? 'Reading plan',
            isGroup: false,
            deleteAfter: progress.deleteAfter!,
          ),
        );
      }

      // Owned groups moved to the trash.
      final groups =
          await widget.groupService.getDeletedGroups(uid).first.timeout(
                const Duration(seconds: 5),
                onTimeout: () => const <Group>[],
              );
      for (final group in groups) {
        if (group.deleteAfter == null) continue;
        items.add(
          _TrashItem(
            id: group.id,
            title: group.name,
            isGroup: true,
            deleteAfter: group.deleteAfter!,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore(_TrashItem item) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    widget.vibrationService.lightImpact();
    try {
      if (item.isGroup) {
        await widget.groupService.restoreGroup(groupId: item.id, ownerUid: uid);
      } else {
        await widget.readingPlanService.restorePlan(uid, item.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${item.title}" restored')),
      );
      await _load();
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  Future<void> _deletePermanently(_TrashItem item) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    widget.vibrationService.lightImpact();
    try {
      if (item.isGroup) {
        await widget.groupService.permanentlyDeleteGroup(
          groupId: item.id,
          ownerUid: uid,
        );
      } else {
        await widget.readingPlanService.permanentlyDeletePlan(uid, item.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${item.title}" deleted permanently'),
        ),
      );
      await _load();
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete — try again')),
        );
      }
    }
  }

  /// Asks before the irreversible purge of one item.
  void _confirmDeletePermanently(_TrashItem item) {
    showDialog(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${item.title}"?'),
        content: const Text(
          'This removes it and its progress permanently. You cannot undo '
          'this.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deletePermanently(item);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  Future<void> _emptyTrash() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null || _items.isEmpty) return;
    widget.vibrationService.lightImpact();
    var failed = false;
    for (final item in List.of(_items)) {
      try {
        if (item.isGroup) {
          await widget.groupService.permanentlyDeleteGroup(
            groupId: item.id,
            ownerUid: uid,
          );
        } else {
          await widget.readingPlanService.permanentlyDeletePlan(uid, item.id);
        }
      } catch (e, st) {
        failed = true;
        ErrorLogger.log(e, st);
      }
    }
    if (!mounted) return;
    if (failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Some items could not be deleted')),
      );
    }
    await _load();
  }

  /// Asks once before emptying the whole trash.
  void _confirmEmptyTrash() {
    showDialog(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Empty Trash?'),
        content: const Text(
          'Everything in the Recently Deleted hub will be removed '
          'permanently. You cannot undo this.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _emptyTrash();
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Empty Trash'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SubHeader(
              title: 'Recently Deleted',
              onBack: () => Navigator.pop(context),
            ),
            if (!_loading && _items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _confirmEmptyTrash,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Empty Trash'),
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? _emptyState(context)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _items.length,
                          itemBuilder: (context, index) =>
                              _trashRow(context, _items[index]),
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
            Icons.delete_outline,
            size: 56,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Nothing here',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Plans and groups you delete wait here for 30 days.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _trashRow(BuildContext context, _TrashItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final days = item.daysLeft(widget.dateProvider());
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              item.isGroup ? Icons.group_outlined : Icons.menu_book_outlined,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '$days day${days == 1 ? '' : 's'} left',
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.tertiary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _restore(item),
            icon: const Icon(Icons.restore),
            tooltip: 'Restore',
            color: colorScheme.primary,
          ),
          IconButton(
            onPressed: () => _confirmDeletePermanently(item),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete permanently',
            color: colorScheme.error.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}
