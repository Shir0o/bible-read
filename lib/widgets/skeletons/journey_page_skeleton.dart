import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../skeleton.dart';

class JourneyPageSkeleton extends StatelessWidget {
  const JourneyPageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // Journey Progress Card Skeleton
          Container(
            padding: const EdgeInsets.all(20),
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
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Skeleton(width: double.infinity, height: 20),
                          const SizedBox(height: 8),
                          const Skeleton(width: 100, height: 12),
                          const SizedBox(height: 16),
                          const Skeleton(width: double.infinity, height: 8),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Skeleton(width: double.infinity, height: 48, radius: 16),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // Bible Library Grid Skeleton
          const Skeleton(width: 140, height: 24),
          const SizedBox(height: 12),
          const Skeleton(width: double.infinity, height: 200, radius: 24),
          const SizedBox(height: 32),
          // Consistency Calendar Skeleton
          const Skeleton(width: 180, height: 24),
          const SizedBox(height: 12),
          const Skeleton(width: double.infinity, height: 150, radius: 24),
        ],
      ),
    );
  }
}
