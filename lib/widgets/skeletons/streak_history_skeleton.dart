import 'package:flutter/material.dart';
import '../common_styles.dart';
import '../skeleton.dart';

class StreakHistorySkeleton extends StatelessWidget {
  const StreakHistorySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Skeleton(width: 200, height: 40, radius: 20),
            ],
          ),
          const SizedBox(height: 12),
          CommonStyles.buildCard(
            context: context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Skeleton(width: 150, height: 16),
                SizedBox(height: 8),
                Skeleton(width: 150, height: 16),
                SizedBox(height: 8),
                Skeleton(width: 150, height: 16),
                SizedBox(height: 8),
                Skeleton(width: 150, height: 16),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Calendar placeholder
          CommonStyles.buildCard(
            context: context,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Skeleton(width: 24, height: 24),
                    Skeleton(width: 100, height: 20),
                    Skeleton(width: 24, height: 24),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(
                      35,
                      (index) =>
                          const Skeleton(width: 32, height: 32, radius: 16)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
