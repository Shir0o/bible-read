import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/read_log.dart';
import '../common_styles.dart';

class CommunityActivityItem extends StatelessWidget {
  final ReadLog log;
  final VoidCallback onLike;

  const CommunityActivityItem({
    super.key,
    required this.log,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Fallback time if timestamp is missing
    final timeString =
        log.timestamp != null ? _timeAgo(log.timestamp!) : 'today';

    final bool isComment = log.comments.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar with badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.surfaceContainerHighest,
                ),
                alignment: Alignment.center,
                child: Text(
                  log.name.isNotEmpty ? log.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color:
                        isComment ? colorScheme.tertiary : colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.surfaceContainer,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    isComment ? Icons.chat_bubble : Icons.check,
                    size: 10,
                    color: isComment
                        ? colorScheme.onTertiary
                        : colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: AppTextStyles.body(
                      context,
                    ).copyWith(color: colorScheme.onSurface),
                    children: [
                      TextSpan(
                        text: log.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (isComment) ...[
                        const TextSpan(text: ' commented on '),
                        TextSpan(
                          text:
                              'daily reading', // Placeholder since we don't have book ref
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else ...[
                        const TextSpan(text: ' completed '),
                        TextSpan(
                          text: 'daily reading',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isComment)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.3,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.1,
                        ),
                      ),
                    ),
                    child: Text(
                      '"${log.comments.last.message}"',
                      style: AppTextStyles.body(context).copyWith(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  timeString,
                  style: AppTextStyles.body(
                    context,
                  ).copyWith(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              log.liked ? Icons.favorite : Icons.favorite_border,
              color:
                  log.liked ? colorScheme.error : colorScheme.onSurfaceVariant,
              size: 20,
            ),
            onPressed: onLike,
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}
