import 'package:flutter/material.dart';
import '../skeleton.dart';

class BibleLibraryGridSkeleton extends StatelessWidget {
  const BibleLibraryGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 8),
          Skeleton(width: double.infinity, height: 200, radius: 24),
        ],
      ),
    );
  }
}
