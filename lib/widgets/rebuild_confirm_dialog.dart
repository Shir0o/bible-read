// Dialog shown on save when a group's plan is about to change in a way that
// drops books from the schedule. The plan can keep a member's existing ticks
// alive (Phase 5a/5b remap by chapter reference), but the dialog still has
// to name what is leaving so the owner makes the call with eyes open.
//
// Triggered from the edit page only when the new plan actually differs and
// at least one member has progress on a chapter that is no longer in the
// plan. A trivial save with no real change skips this dialog outright.
import 'package:flutter/material.dart';

import '../models/group_plan_config.dart';
import '../models/group_schedule.dart';
import '../services/progress_remap.dart';
import '../services/schedule_generator.dart';
import '../theme/app_theme.dart';
import 'group_plan_keys.dart';
import 'plan_day_list.dart';

/// Opens the rebuild confirmation. Returns true if the owner confirmed.
Future<bool> showRebuildConfirmDialog({
  required BuildContext context,
  required GroupPlanDraft oldDraft,
  required GroupPlanDraft newDraft,
  required List<GroupSchedule> newDays,
  required ProgressRemap remap,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.of(context).scrim,
    builder: (context) => _RebuildConfirmDialog(
      oldDraft: oldDraft,
      newDraft: newDraft,
      newDays: newDays,
      remap: remap,
    ),
  );
  return result ?? false;
}

class _RebuildConfirmDialog extends StatelessWidget {
  final GroupPlanDraft oldDraft;
  final GroupPlanDraft newDraft;
  final List<GroupSchedule> newDays;
  final ProgressRemap remap;

  const _RebuildConfirmDialog({
    required this.oldDraft,
    required this.newDraft,
    required this.newDays,
    required this.remap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = AppTheme.uiTextTheme(theme.textTheme);

    final newPlan = ScheduleGenerator.planFromDraft(newDraft);
    final totalDroppedRefs = _totalDroppedRefs();
    final droppedByBook = _aggregateDroppedByBook();

    return AlertDialog(
      key: GroupPlanKeys.rebuildConfirmDialog,
      title: const Text('Rebuild the schedule?'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _leadIn(newPlan),
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Everything the group has already read stays marked — '
              'Jeremiah 3 will still be ticked wherever it lands.',
              style: textTheme.bodyMedium,
            ),
            if (droppedByBook.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _booksLeavingLine(droppedByBook),
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _chaptersLeavingLine(totalDroppedRefs),
                style: textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: GroupPlanKeys.rebuildConfirmAccept,
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Rebuild'),
        ),
      ],
    );
  }

  String _leadIn(GeneratedPlan newPlan) {
    final start = newDraft.startRef.isEmpty ? 'chapter 1' : newDraft.startRef;
    final dayCount = newPlan.days.length;
    final finish = newPlan.finishesOn;
    if (finish == null) {
      return 'The plan will start at $start and run $dayCount days.';
    }
    return 'The plan will start at $start and run $dayCount days, '
        'finishing ${formatPlanDateShort(finish)}.';
  }

  /// Books dropped across the whole group, sorted by chapter count.
  List<MapEntry<String, int>> _aggregateDroppedByBook() {
    final totals = <String, int>{};
    remap.droppedByBook.forEach((_, byBook) {
      byBook.forEach((book, count) {
        totals.update(book, (n) => n + count, ifAbsent: () => count);
      });
    });
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  int _totalDroppedRefs() {
    var total = 0;
    remap.droppedByBook.forEach((_, byBook) {
      byBook.forEach((_, count) {
        total += count;
      });
    });
    return total;
  }

  String _booksLeavingLine(List<MapEntry<String, int>> entries) {
    if (entries.isEmpty) return '';
    if (entries.length == 1) {
      final e = entries.first;
      return '${e.value} chapters of ${e.key} leave the plan.';
    }
    final formatted = entries.map((e) => '${e.value} of ${e.key}').toList();
    final last = formatted.removeLast();
    return '${formatted.join(', ')} and $last leave the plan.';
  }

  String _chaptersLeavingLine(int total) {
    if (total == 0) return '';
    if (total == 1) {
      return '1 chapter the group had already read will no longer count.';
    }
    return '$total chapters the group had already read will no longer count.';
  }
}
