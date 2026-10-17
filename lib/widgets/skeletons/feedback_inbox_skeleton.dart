import 'package:flutter/material.dart';

import '../skeleton.dart';
import '../../theme/app_theme.dart';

/// Placeholder for one Feedback Inbox tab's list: cards with a title, two
/// meta lines and the action buttons, matching `_FeedbackEntryCard`.
class FeedbackCardsSkeleton extends StatelessWidget {
  const FeedbackCardsSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            const Card(
              margin: EdgeInsets.symmetric(
                horizontal: AppSpacing.gap16,
                vertical: AppSpacing.gap8,
              ),
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.gap16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton(width: 180, height: 16),
                    SizedBox(height: AppSpacing.gap12),
                    Skeleton(width: 140, height: 12),
                    SizedBox(height: AppSpacing.gap8),
                    Skeleton(height: 12),
                    SizedBox(height: AppSpacing.gap16),
                    Row(
                      children: [
                        Skeleton(width: 120, height: 36, radius: 18),
                        SizedBox(width: AppSpacing.gap8),
                        Skeleton(width: 150, height: 36, radius: 18),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Placeholder for the whole Inbox while the admin check runs: tab bar, status
/// filter, then [FeedbackCardsSkeleton] — the same cards each tab shows while
/// its stream loads, so the hand-off between the two skeletons is seamless.
class FeedbackInboxSkeleton extends StatelessWidget {
  const FeedbackInboxSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).colorScheme.outlineVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 72,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: const Row(
            children: [
              Expanded(child: Center(child: Skeleton(width: 96, height: 14))),
              Expanded(child: Center(child: Skeleton(width: 120, height: 14))),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.gap16,
            AppSpacing.gap16,
            AppSpacing.gap16,
            AppSpacing.gap8,
          ),
          child: Skeleton(height: 44, radius: AppSpacing.rInset),
        ),
        const Expanded(child: FeedbackCardsSkeleton()),
      ],
    );
  }
}
