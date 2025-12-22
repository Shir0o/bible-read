import 'package:flutter/material.dart';
import '../common_styles.dart';
import '../skeleton.dart';

class FriendsSkeleton extends StatelessWidget {
  const FriendsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: 8,
      itemBuilder: (context, index) {
        return CommonStyles.buildTappableCard(
          context: context,
          onTap: () {},
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: const [
                Expanded(
                  child: Skeleton(width: 120, height: 16),
                ),
                SizedBox(width: 16),
                Skeleton(width: 40, height: 40, radius: 20), // Icon Button
              ],
            ),
          ),
        );
      },
    );
  }
}
