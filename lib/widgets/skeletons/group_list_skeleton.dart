import 'package:flutter/material.dart';
import '../common_styles.dart';
import '../skeleton.dart';

class GroupListSkeleton extends StatelessWidget {
  const GroupListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: 5,
      separatorBuilder: (_, __) => const Divider(height: 0),
      itemBuilder: (context, index) {
        return CommonStyles.buildTappableCard(
          context: context,
          onTap: () {},
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                       Skeleton(width: 140, height: 16),
                       SizedBox(height: 8),
                       Skeleton(width: 80, height: 12),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                const Skeleton(width: 40, height: 12), // "Pending" placeholder or similar
              ],
            ),
          ),
        );
      },
    );
  }
}
