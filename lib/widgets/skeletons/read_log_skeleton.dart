import 'package:flutter/material.dart';
import '../common_styles.dart';
import '../skeleton.dart';

class ReadLogSkeleton extends StatelessWidget {
  const ReadLogSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding:
          const EdgeInsets.only(top: 16.0, bottom: 48.0, left: 16, right: 16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return CommonStyles.buildTappableCard(
          context: context,
          onTap: () {},
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2.0),
                      child: Skeleton(width: 20, height: 20, radius: 10),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Skeleton(width: 160, height: 16),
                          SizedBox(height: 6),
                          Skeleton(width: 100, height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.only(left: 32.0),
                  child: Row(
                    children: const [
                      Skeleton(width: 24, height: 24, radius: 12),
                      SizedBox(width: 16),
                      Skeleton(width: 24, height: 24, radius: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
