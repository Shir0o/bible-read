import 'package:flutter/material.dart';
import '../common_styles.dart';
import '../skeleton.dart';

class ReadStatusSkeleton extends StatelessWidget {
  const ReadStatusSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Read Toggle Card Skeleton
        CommonStyles.buildCard(
          context: context,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Skeleton(width: 150, height: 20),
                const SizedBox(width: 24),
                Skeleton(width: 50, height: 30, radius: 16),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Streak Freezes Text Skeleton
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: const Skeleton(width: 180, height: 16),
          ),
        ),
        const SizedBox(height: 16),

        // Week Calendar Skeleton
        CommonStyles.buildCard(
          context: context,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title "Week of..."
              const Skeleton(width: 100, height: 16),
              const SizedBox(height: 16),
              // Content block representing the week days
              const Skeleton(width: double.infinity, height: 40, radius: 12),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Month Calendar Skeleton
        CommonStyles.buildCard(
          context: context,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title "Month - Year"
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Skeleton(width: 24, height: 24), // Arrow
                  const SizedBox(width: 16),
                  const Skeleton(width: 120, height: 16), // Title
                  const SizedBox(width: 16),
                  const Skeleton(width: 24, height: 24), // Arrow
                ],
              ),
              const SizedBox(height: 16),
              // Content block representing the month grid
              const Skeleton(width: double.infinity, height: 180, radius: 12),
            ],
          ),
        ),
      ],
    );
  }
}
