import 'package:flutter/material.dart';
import '../skeleton.dart';

class HomePageSkeleton extends StatelessWidget {
  const HomePageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon Skeleton
            const Skeleton(
              width: 80,
              height: 80,
              shape: CircleBorder(),
            ),
            const SizedBox(height: 24),
            // "Marked Today" Title Skeleton
            const Skeleton(
              width: 180,
              height: 32,
              radius: 8,
            ),
            const SizedBox(height: 12),
            // Subtitle Skeleton
            const Skeleton(
              width: 220,
              height: 20,
              radius: 4,
            ),
            const SizedBox(height: 48),
            // Button Skeleton (Full width)
            const Skeleton(
              width: double.infinity,
              height: 80,
              radius: 24,
            ),
            const SizedBox(height: 48),

            // Weekly Progress Title Skeleton
            const Skeleton(
              width: 100,
              height: 14,
              radius: 4,
            ),
            const SizedBox(height: 8),
            // Progress Bar Skeleton (Constrained width in real app is 240)
            const Skeleton(
              width: 240,
              height: 6,
              radius: 4,
            ),
            const SizedBox(height: 24),

            // Streak Text Skeleton
            const Skeleton(
              width: 120,
              height: 16,
              radius: 4,
            ),
          ],
        ),
      ),
    );
  }
}
