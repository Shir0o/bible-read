import 'package:flutter/material.dart';
import '../skeleton.dart';

class PlansHubSkeleton extends StatelessWidget {
  const PlansHubSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        // Section Heading Skeleton
        Row(
          children: const [
            Skeleton(width: 20, height: 20, radius: 4),
            SizedBox(width: 8),
            Skeleton(width: 120, height: 16),
          ],
        ),
        const SizedBox(height: 12),
        // Plan Card Skeleton
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Skeleton(width: 48, height: 48, radius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Skeleton(width: 140, height: 18),
                        SizedBox(height: 6),
                        Skeleton(width: 100, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Skeleton(width: double.infinity, height: 6, radius: 3),
              const SizedBox(height: 16),
              Row(
                children: const [
                  Expanded(
                    child: Skeleton(
                      width: double.infinity,
                      height: 38,
                      radius: 10,
                    ),
                  ),
                  SizedBox(width: 8),
                  Skeleton(width: 38, height: 38, radius: 10),
                  SizedBox(width: 8),
                  Skeleton(width: 38, height: 38, radius: 10),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
