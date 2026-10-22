import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_bottom_sheet.dart';
import 'common_styles.dart';

/// What the reader chose on [DeletePlanSheet].
enum PlanRemovalChoice { remove, archive }

/// Confirms taking a Shared plan off Path: the owner deletes it for everyone,
/// a member leaves it. Both offer "Archive instead" as the gentler way out.
///
/// Resolves to the reader's [PlanRemovalChoice], or `null` if dismissed.
class DeletePlanSheet extends StatelessWidget {
  final String planName;
  final bool isOwner;

  /// How many readers the plan has; `0` when unknown.
  final int readerCount;

  const DeletePlanSheet({
    super.key,
    required this.planName,
    required this.isOwner,
    this.readerCount = 0,
  });

  static Future<PlanRemovalChoice?> show(
    BuildContext context, {
    required String planName,
    required bool isOwner,
    int readerCount = 0,
  }) {
    return showAppSheet<PlanRemovalChoice>(
      context: context,
      builder: (context) => DeletePlanSheet(
        planName: planName,
        isOwner: isOwner,
        readerCount: readerCount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final readers = readerCount > 0
        ? 'for all $readerCount reader${readerCount == 1 ? '' : 's'}'
        : 'for everyone';
    final lines = isOwner
        ? [
            (
              Icons.people_outline,
              'The plan ends $readers, and it leaves their Path.',
            ),
            (
              Icons.check_circle_outline,
              'Chapters people already read stay in their history.',
            ),
            (
              Icons.restore,
              'You can restore it from Recently Deleted for 30 days.',
            ),
          ]
        : [
            (Icons.people_outline, 'The plan carries on for everyone else.'),
            (
              Icons.check_circle_outline,
              'Your marks on this plan are removed.',
            ),
          ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gap24, AppSpacing.gap8,
          AppSpacing.gap12, AppSpacing.gap24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.gap8),
                  child: Text(
                    '${isOwner ? 'Delete' : 'Leave'} “$planName”?',
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                color: colorScheme.onSurfaceVariant,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.gap16),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.gap12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (icon, text) in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.gap12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          icon,
                          size: AppSpacing.iconMd,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.gap12),
                        Expanded(
                          child: Text(
                            text,
                            style: AppTextStyles.body(context).copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.gap8),
                FilledButton(
                  style: AppButtonStyles.destructiveFilled(context),
                  onPressed: () =>
                      Navigator.of(context).pop(PlanRemovalChoice.remove),
                  child: Text(isOwner ? 'Delete for everyone' : 'Leave plan'),
                ),
                const SizedBox(height: AppSpacing.gap8),
                OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(PlanRemovalChoice.archive),
                  child: const Text('Archive instead'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
