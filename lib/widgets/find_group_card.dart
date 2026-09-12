import 'package:flutter/material.dart';

import '../models/group.dart';
import '../theme/app_theme.dart';
import 'common_styles.dart';

/// A compact public-group row for the "Find a group" browse sheet.
///
/// Shows only what a non-member is allowed to see before approval: the Group
/// name, what it is reading, and its member count. Member names, photos, and
/// daily Progress are deliberately absent (ADR-0003); tapping the row opens
/// the Group preview for the request-to-join flow.
class FindGroupCard extends StatelessWidget {
  /// The public Group being browsed.
  final Group group;

  /// The non-member-safe reading summary.
  final String readingSummary;

  /// Opens the Group preview.
  final VoidCallback onTap;

  const FindGroupCard({
    super.key,
    required this.group,
    required this.readingSummary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final count = group.memberCount;
    final countLabel = count == 1 ? '1 member' : '$count members';

    return CommonStyles.buildTappableCard(
      context: context,
      margin: const EdgeInsets.only(bottom: 10),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title(context).copyWith(
                    fontFamily: AppTheme.fontSerif,
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$readingSummary / $countLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            Icons.chevron_right,
            color: colorScheme.onSurfaceVariant,
            size: 20,
          ),
        ],
      ),
    );
  }
}
