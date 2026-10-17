import 'package:flutter/material.dart';

import '../skeleton.dart';
import '../../theme/app_theme.dart';

/// Placeholder for the notification center: bordered cards with a 48px avatar
/// and two text lines, laid out like the loaded list so nothing jumps.
class NotificationListSkeleton extends StatelessWidget {
  const NotificationListSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    final border = AppColors.of(context).border;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gap16,
          AppSpacing.gap8,
          AppSpacing.gap16,
          AppSpacing.gap24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.gap8),
                padding: const EdgeInsets.all(AppSpacing.gap16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.rInset),
                  border: Border.all(color: border),
                ),
                child: const Row(
                  children: [
                    Skeleton(width: 48, height: 48, shape: CircleBorder()),
                    SizedBox(width: AppSpacing.gap12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Skeleton(height: 14),
                          SizedBox(height: AppSpacing.gap8),
                          Skeleton(width: 56, height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
