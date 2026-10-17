import 'package:flutter/material.dart';

import '../skeleton.dart';

/// Generic placeholder for a short vertical list of rows (members, requests,
/// notifications, settings toggles...). Non-scrolling so it can sit inside any
/// parent; the real list owns scrolling once content lands.
class ListRowsSkeleton extends StatelessWidget {
  const ListRowsSkeleton({
    super.key,
    this.count = 4,
    this.showAvatar = true,
    this.padding = const EdgeInsets.all(16),
  });

  final int count;
  final bool showAvatar;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  if (showAvatar) ...[
                    const Skeleton(
                      width: 40,
                      height: 40,
                      shape: CircleBorder(),
                    ),
                    const SizedBox(width: 12),
                  ],
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton(width: 140, height: 14),
                        SizedBox(height: 8),
                        Skeleton(width: 90, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
