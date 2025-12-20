import 'package:flutter/material.dart';
import '../common_styles.dart';
import '../skeleton.dart';

class FriendlyStreakSkeleton extends StatelessWidget {
  const FriendlyStreakSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return CommonStyles.buildCard(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // Icon Circle
            const Skeleton(
              width: 56,
              height: 56,
              radius: 28,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title "Friendly streaks"
                  const Skeleton(width: 120, height: 14),
                  const SizedBox(height: 8),
                  // Subtitle / Status
                  const Skeleton(width: 200, height: 16),
                  const SizedBox(height: 12),
                  // List Items
                  const Skeleton(width: 180, height: 14),
                  const SizedBox(height: 8),
                  const Skeleton(width: 160, height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
