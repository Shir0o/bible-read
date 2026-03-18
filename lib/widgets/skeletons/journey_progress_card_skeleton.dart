import 'package:flutter/material.dart';
import '../skeleton.dart';

class JourneyProgressCardSkeleton extends StatelessWidget {
  const JourneyProgressCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
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
    );
  }
}
