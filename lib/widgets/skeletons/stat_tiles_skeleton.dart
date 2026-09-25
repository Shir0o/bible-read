import 'package:flutter/material.dart';
import '../skeleton.dart';

/// Two side-by-side placeholders for the Path tab's stat tiles ("Shown up"
/// and "Day streak"), mirroring the loaded tile layout so the swap does not
/// shift.
class StatTilesSkeleton extends StatelessWidget {
  const StatTilesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _tile(colorScheme)),
            const SizedBox(width: 12),
            Expanded(child: _tile(colorScheme)),
          ],
        ),
      ),
    );
  }

  Widget _tile(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(width: 64, height: 28),
          SizedBox(height: 12),
          Skeleton(width: 88, height: 14),
          SizedBox(height: 6),
          Skeleton(width: 56, height: 12),
        ],
      ),
    );
  }
}
