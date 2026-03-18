import 'package:flutter/material.dart';
import '../skeleton.dart';

class ConsistencyCalendarSkeleton extends StatelessWidget {
  const ConsistencyCalendarSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 12),
          Skeleton(width: double.infinity, height: 150, radius: 24),
        ],
      ),
    );
  }
}
