import 'package:flutter/material.dart';
import '../common_styles.dart';
import '../skeleton.dart';
import '../../theme/app_theme.dart';

class ReadLogSkeleton extends StatelessWidget {
  const ReadLogSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(
        top: AppSpacing.gap16,
        bottom: 48.0,
        left: AppSpacing.gap16,
        right: AppSpacing.gap16,
      ),
      itemCount: 5,
      itemBuilder: (context, index) {
        return CommonStyles.buildTappableCard(
          context: context,
          onTap: () {},
          margin: const EdgeInsets.symmetric(
              vertical: AppSpacing.gap8, horizontal: AppSpacing.gap4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gap16,
                AppSpacing.gap16, AppSpacing.gap16, AppSpacing.gap12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpacing.gap2),
                      child: Skeleton(width: 20, height: 20, radius: 10),
                    ),
                    const SizedBox(width: AppSpacing.gap12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Skeleton(width: 160, height: 16),
                          SizedBox(height: AppSpacing.gap6),
                          Skeleton(width: 100, height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.gap24),
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.gap32),
                  child: Row(
                    children: const [
                      Skeleton(width: 24, height: 24, radius: 12),
                      SizedBox(width: AppSpacing.gap16),
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
