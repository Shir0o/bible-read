import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../skeleton.dart';

/// A placeholder for the "next up" badge card on the Path tab while the badge
/// and read-through ledgers are still loading.
class BadgeNextUpSkeleton extends StatelessWidget {
  const BadgeNextUpSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: const Row(
        children: [
          Skeleton(width: 38, height: 38),
          SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 120, height: 14),
                SizedBox(height: 6),
                Skeleton(width: 180, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
