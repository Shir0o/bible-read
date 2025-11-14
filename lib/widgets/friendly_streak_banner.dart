import 'package:flutter/material.dart';

import '../services/friend_service.dart';
import '../services/friendly_streak_service.dart';
import '../theme/app_theme.dart';

/// Highlights the highest streak among the user's friends.
class FriendlyStreakBanner extends StatelessWidget {
  /// Active and pending streak data for the current user.
  final FriendlyStreakLinksSummary summary;

  /// Whether the banner is still loading data.
  final bool isLoading;

  /// Optional tap handler to navigate to streak history.
  final VoidCallback? onTap;

  const FriendlyStreakBanner({
    super.key,
    required this.summary,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final onPrimary = colorScheme.onPrimary;
    final activeLinks = summary.activeLinks;
    final pendingLinks = summary.pendingLinks;
    final reachedLimit =
        activeLinks.length >= FriendService.maxActiveStreakLinks;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.hPadding,
        vertical: AppSpacing.vPaddingSmall,
      ),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colorScheme.secondary, colorScheme.primary],
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: onPrimary.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(14),
                child: Icon(
                  Icons.local_fire_department,
                  color: onPrimary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Friendly streaks',
                      style: textTheme.labelLarge?.copyWith(
                        color: onPrimary.withValues(alpha: 0.88),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (isLoading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'Checking your streak partners...',
                          style: textTheme.bodyMedium?.copyWith(
                            color: onPrimary,
                          ),
                        ),
                      )
                    else if (!summary.hasPartners)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'Invite up to ${FriendService.maxActiveStreakLinks} friends to share streaks.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: onPrimary.withValues(alpha: 0.9),
                          ),
                        ),
                      )
                    else ...[
                      Text(
                        'Active partners (${activeLinks.length}/${FriendService.maxActiveStreakLinks})',
                        style: textTheme.titleMedium?.copyWith(
                          color: onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...activeLinks.map(
                        (link) => _FriendlyLinkRow(
                          name: link.partnerName ?? 'Friend',
                          detail:
                              '${link.currentStreak} day${link.currentStreak == 1 ? '' : 's'}',
                          icon: Icons.local_fire_department,
                          iconColor: onPrimary,
                        ),
                      ),
                      if (pendingLinks.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Pending invites (${pendingLinks.length})',
                          style: textTheme.titleSmall?.copyWith(
                            color: onPrimary.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...pendingLinks.map(
                          (link) => _FriendlyLinkRow(
                            name: link.partnerName ?? 'Friend',
                            detail: link.isIncoming
                                ? 'Respond to invite'
                                : 'Waiting for partner',
                            icon: Icons.hourglass_top,
                            iconColor: onPrimary,
                          ),
                        ),
                      ],
                    ],
                    if (reachedLimit) ...[
                      const SizedBox(height: 8),
                      Text(
                        'You reached the limit of ${FriendService.maxActiveStreakLinks} active streak partners.',
                        style: textTheme.bodySmall?.copyWith(
                          color: onPrimary.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                    if (onTap != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View history',
                            style: textTheme.labelLarge?.copyWith(
                              color: onPrimary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_forward, color: onPrimary, size: 18),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendlyLinkRow extends StatelessWidget {
  const _FriendlyLinkRow({
    required this.name,
    required this.detail,
    required this.icon,
    required this.iconColor,
  });

  final String name;
  final String detail;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: iconColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: iconColor.withValues(alpha: 0.9),
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
