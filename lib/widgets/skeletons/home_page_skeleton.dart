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
            // "Did you read today?" Title Skeleton
            // Size 24 font ~ 32px height visually including line height
            const Skeleton(width: 220, height: 32, radius: 8),

            const SizedBox(height: 48),

            // "Yes, I read" Button Skeleton (Full width)
            const Skeleton(width: double.infinity, height: 80, radius: 24),
          ],
        ),
      ),
    );
  }
}
