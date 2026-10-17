import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../skeleton.dart';

class JourneyPageSkeleton extends StatelessWidget {
  const JourneyPageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.gap16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.gap16),
          // Journey Progress Card Skeleton
          Container(
            padding: const EdgeInsets.all(AppSpacing.gap20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppSpacing.rCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Skeleton(width: 80, height: 100, radius: 16),
                    const SizedBox(width: AppSpacing.gap16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Skeleton(width: double.infinity, height: 20),
                          const SizedBox(height: AppSpacing.gap8),
                          const Skeleton(width: 100, height: 12),
                          const SizedBox(height: AppSpacing.gap16),
                          const Skeleton(width: double.infinity, height: 8),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.gap20),
                const Skeleton(width: double.infinity, height: 48, radius: 16),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.gap32),
          // Bible Library Grid Skeleton
          const Skeleton(width: 140, height: 24),
          const SizedBox(height: AppSpacing.gap12),
          const Skeleton(width: double.infinity, height: 200, radius: 24),
          const SizedBox(height: AppSpacing.gap32),
          // Consistency Calendar Skeleton
          const Skeleton(width: 180, height: 24),
          const SizedBox(height: AppSpacing.gap12),
          const Skeleton(width: double.infinity, height: 150, radius: 24),
        ],
      ),
    );
  }
}
