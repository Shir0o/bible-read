import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../skeleton.dart';

/// Loading placeholder for [HomePage].
///
/// Mirrors the real top-aligned layout (design parity): the header (eyebrow
/// date + greeting + avatar), the habit hero, a "Today's reading" card with its
/// catch-up banner, the consistency glimpse and the bottom community card — so
/// the transition into loaded content doesn't jump.
class HomePageSkeleton extends StatelessWidget {
  const HomePageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      // The skeleton stands in for a (scrollable) page but is itself rendered
      // outside a scroll view, so wrap it to absorb any overflow on short
      // screens rather than painting the debug overflow stripes.
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.hPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.gap8),
              // Header: eyebrow date + greeting on the left, avatar on the right.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: const [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton(width: 130, height: 11, radius: 6),
                        SizedBox(height: AppSpacing.gap8),
                        Skeleton(width: 180, height: 26, radius: 8),
                      ],
                    ),
                  ),
                  SizedBox(width: AppSpacing.gap12),
                  Skeleton(width: 40, height: 40, shape: CircleBorder()),
                ],
              ),

              const SizedBox(height: AppSpacing.gap24),
              // Habit hero card.
              const Skeleton(width: double.infinity, height: 210, radius: 28),

              const SizedBox(height: AppSpacing.gap32),
              // "Today's reading" section label + card.
              const Align(
                alignment: Alignment.centerLeft,
                child: Skeleton(width: 120, height: 14, radius: 6),
              ),
              const SizedBox(height: AppSpacing.gap12),
              const Skeleton(width: double.infinity, height: 150, radius: 24),

              const SizedBox(height: AppSpacing.gap8),
              // Catch-up banner.
              const Skeleton(width: double.infinity, height: 62, radius: 14),

              const SizedBox(height: AppSpacing.gap40),
              // Consistency glimpse.
              const Skeleton(width: double.infinity, height: 76, radius: 20),

              const SizedBox(height: AppSpacing.gap32),
              // "Your community" label + card.
              const Align(
                alignment: Alignment.centerLeft,
                child: Skeleton(width: 120, height: 14, radius: 6),
              ),
              const SizedBox(height: AppSpacing.gap12),
              const Skeleton(width: double.infinity, height: 76, radius: 20),
            ],
          ),
        ),
      ),
    );
  }
}
