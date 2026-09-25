import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../skeleton.dart';

/// The "Times through" card shell with skeleton bars in place of the three
/// count boxes, shown while the read-through ledger is still loading. The
/// card's title stays visible, per the app's skeleton convention.
class ReadThroughCardSkeleton extends StatelessWidget {
  const ReadThroughCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appColors = AppColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.rCard),
          border: Border.all(color: appColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Times through', style: textTheme.titleLarge),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: const [
                Expanded(child: _CountBox(accented: true)),
                SizedBox(width: 10),
                Expanded(child: _CountBox()),
                SizedBox(width: 10),
                Expanded(child: _CountBox()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBox extends StatelessWidget {
  final bool accented;

  const _CountBox({this.accented = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: accented
            ? AppColors.of(context).accentSoft
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.rInset),
        border: Border.all(
          color: accented
              ? colorScheme.tertiary.withValues(alpha: 0.28)
              : AppColors.of(context).border,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(width: 44, height: 24),
          SizedBox(height: 8),
          Skeleton(width: 72, height: 12),
        ],
      ),
    );
  }
}
