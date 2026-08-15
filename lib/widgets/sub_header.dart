import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Sub-screen header matching the design's `SubHeader`: a 40px back chevron on
/// the left, a serif title, and optional right-hand actions.
class SubHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? right;
  final bool showBack;

  const SubHeader({
    super.key,
    required this.title,
    this.onBack,
    this.right,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Row(
        children: [
          if (showBack && onBack != null)
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                tooltip: 'Back',
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.chevron_left,
                  size: 28,
                  color: colorScheme.onSurface,
                ),
                onPressed: onBack,
              ),
            ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontFamily: AppTheme.fontSerif,
                    fontWeight: FontWeight.w500,
                    fontSize: 24,
                    letterSpacing: -0.2,
                    color: colorScheme.onSurface,
                  ),
            ),
          ),
          if (right != null) right!,
        ],
      ),
    );
  }
}
