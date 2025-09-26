import 'package:flutter/material.dart';

import 'common_styles.dart';

/// Standard section header with consistent styling and spacing.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});

  /// Header text.
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.subtitle),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
