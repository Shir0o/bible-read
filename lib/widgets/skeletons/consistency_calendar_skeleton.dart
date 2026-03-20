import 'package:flutter/material.dart';
import '../skeleton.dart';

class ConsistencyCalendarSkeleton extends StatelessWidget {
  const ConsistencyCalendarSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Skeleton(width: double.infinity, height: 150, radius: 24);
  }
}
