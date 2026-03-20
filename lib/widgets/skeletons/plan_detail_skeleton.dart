import 'package:flutter/material.dart';
import '../skeleton.dart';

class PlanDetailSkeleton extends StatelessWidget {
  const PlanDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Description
          const Padding(
            padding: EdgeInsets.only(bottom: 24, left: 8, right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: double.infinity, height: 16),
                SizedBox(height: 8),
                Skeleton(width: 200, height: 16),
              ],
            ),
          ),

          // Today Section Header
          _buildSectionHeader(context),
          _buildSkeletonItem(context, isToday: true),
          const SizedBox(height: 16),

          // Upcoming Section Header
          _buildSectionHeader(context),
          ...List.generate(5, (index) => _buildSkeletonItem(context)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 8, bottom: 8, top: 8),
      child: Skeleton(width: 100, height: 12),
    );
  }

  Widget _buildSkeletonItem(BuildContext context, {bool isToday = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isToday
            ? Theme.of(context).colorScheme.surfaceContainer
            : Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(isToday ? 24 : 16),
        border: isToday
            ? Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
              )
            : null,
      ),
      padding: EdgeInsets.all(isToday ? 20 : 16),
      child: Row(
        children: [
          const SizedBox(
            width: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 40, height: 10),
                SizedBox(height: 4),
                Skeleton(width: 30, height: 10),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 60, height: 10),
                SizedBox(height: 6),
                Skeleton(width: double.infinity, height: 14),
              ],
            ),
          ),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
            ),
          )
        ],
      ),
    );
  }
}
