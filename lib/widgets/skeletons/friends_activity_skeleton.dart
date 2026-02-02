import 'package:flutter/material.dart';
import '../skeleton.dart';

class FriendsActivitySkeleton extends StatelessWidget {
  const FriendsActivitySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          return const _ActivityItemSkeleton();
        },
        childCount: 5, // Show 5 skeleton items
      ),
    );
  }
}

class _ActivityItemSkeleton extends StatelessWidget {
  const _ActivityItemSkeleton();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Skeleton(width: 40, height: 40, radius: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Skeleton(width: 140, height: 16),
                const SizedBox(height: 8),
                const Skeleton(width: 60, height: 12),
                const SizedBox(height: 12),
                Skeleton(
                  width: double.infinity,
                  height: 36,
                  radius: 12,
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Skeleton(width: 24, height: 24, radius: 12),
        ],
      ),
    );
  }
}
