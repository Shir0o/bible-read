import 'package:flutter/material.dart';
import '../skeleton.dart';

class PostReadSkeleton extends StatelessWidget {
  const PostReadSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Checkmark Icon Skeleton
            const Skeleton(
              width: 80,
              height: 80,
              radius: 40, // Circular
            ),

            const SizedBox(height: 24),

            // "Thank you for being here" Text Skeleton
            const Skeleton(
              width: 200,
              height: 32,
              radius: 8,
            ),

            const Spacer(),

            // Weekly Progress Section (Constrained width to 240)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // "Reading this week" Label
                    const Skeleton(
                      width: 100,
                      height: 12,
                      radius: 4,
                    ),
                    const SizedBox(height: 8),
                    // Progress Bar
                    const Skeleton(
                      width: 240,
                      height: 10,
                      radius: 8,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Streak Text Skeleton
            const Skeleton(
              width: 120,
              height: 16,
              radius: 4,
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
