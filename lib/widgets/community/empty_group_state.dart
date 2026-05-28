import 'package:flutter/material.dart';
import '../common_styles.dart';

class EmptyGroupState extends StatelessWidget {
  const EmptyGroupState({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.1),
        ),
      ),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.group_outlined,
            size: 48,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No active groups',
            style: AppTextStyles.title(
              context,
            ).copyWith(fontSize: 16, color: colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            'Join a group to see progress here.',
            style: AppTextStyles.body(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
