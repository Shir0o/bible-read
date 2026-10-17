import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../skeleton.dart';

/// Placeholder for the Path tab's Consistency card: the two header figures
/// and the calendar, in the same card surface so the swap does not shift.
class ConsistencyCardSkeleton extends StatelessWidget {
  const ConsistencyCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: AppSpacing.horizontal,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.rCard),
          border: Border.all(color: AppColors.of(context).border),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _Figure()),
                SizedBox(width: AppSpacing.gap12),
                Expanded(child: _Figure()),
              ],
            ),
            SizedBox(height: AppSpacing.gap16),
            Skeleton(width: double.infinity, height: 150, radius: 24),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Skeleton(width: 64, height: 28),
        SizedBox(height: AppSpacing.gap6),
        Skeleton(width: 96, height: 14),
      ],
    );
  }
}
