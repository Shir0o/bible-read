import 'package:flutter/material.dart';
import '../skeleton.dart';

class ReadLogEmptySkeleton extends StatelessWidget {
  const ReadLogEmptySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Skeleton(width: 48, height: 48, radius: 24), // Icon
            SizedBox(height: 16),
            Skeleton(width: 180, height: 20, radius: 4), // Title "Be the first light today"
            SizedBox(height: 8),
            Skeleton(width: 240, height: 16, radius: 4), // Subtitle
            SizedBox(height: 4),
            Skeleton(width: 200, height: 16, radius: 4), // Subtitle line 2
          ],
        ),
      ),
    );
  }
}
