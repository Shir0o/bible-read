import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'common_styles.dart';
import 'group_plan_keys.dart';

/// Shows where a reading plan begins, and what that leaves out.
///
/// The count of skipped chapters is stated plainly rather than implied, so a
/// reader can see the cost of their start point before creating the plan.
class StartsAtCard extends StatelessWidget {
  /// Reference day one begins with, e.g. `'Jeremiah 1'`.
  final String startRef;

  /// Chapters ahead of [startRef] that will not be scheduled.
  final int skippedBefore;

  final VoidCallback onChange;

  const StartsAtCard({
    super.key,
    required this.startRef,
    required this.skippedBefore,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);

    return Container(
      key: GroupPlanKeys.startsAtCard,
      decoration: BoxDecoration(
        color: appColors.primarySoft,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(color: appColors.primaryLine),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('STARTS AT', style: AppTextStyles.eyebrow(context)),
                    const SizedBox(height: 3),
                    Text(
                      startRef.isEmpty ? 'The beginning' : startRef,
                      key: GroupPlanKeys.startRefText,
                      style: TextStyle(
                        fontFamily: AppTheme.fontSerif,
                        fontSize: 26,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.4,
                        height: 1.1,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.gap12),
              OutlinedButton.icon(
                key: GroupPlanKeys.changeStartButton,
                onPressed: onChange,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right, size: 16),
                label: const Text('Change'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  backgroundColor: colorScheme.surfaceContainerLowest,
                  foregroundColor: appColors.primaryPress,
                  side: BorderSide(color: appColors.primaryLine),
                  textStyle: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Divider(height: 1, thickness: 1, color: appColors.primaryLine),
          const SizedBox(height: 11),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.gap8),
              Expanded(
                child: Text(
                  skippedBefore == 0
                      ? 'Nothing is left out — the plan begins at the beginning.'
                      : '$skippedBefore chapters before '
                          '$startRef will not be scheduled.',
                  key: GroupPlanKeys.skipNote,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
