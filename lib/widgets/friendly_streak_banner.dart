import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Highlights the highest streak among the user's friends.
class FriendlyStreakBanner extends StatelessWidget {
  /// Top streak value to display.
  final int? streak;

  /// Whether the banner is still loading data.
  final bool isLoading;

  /// Optional tap handler to navigate to streak history.
  final VoidCallback? onTap;

  const FriendlyStreakBanner({
    super.key,
    this.streak,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final onPrimary = colorScheme.onPrimary;

    final streakText = isLoading
        ? 'Checking your friends...'
        : streak != null
        ? '$streak day${streak == 1 ? '' : 's'} in a row'
        : 'No friend streak data yet';

    final subtitle = streak != null
        ? 'Keep reading to catch up or stay ahead!'
        : 'Add friends to start a friendly challenge.';

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
                      'Friendly streak leader',
                      style: textTheme.labelLarge?.copyWith(
                        color: onPrimary.withValues(alpha: 0.88),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      streakText,
                      style:
                          textTheme.displaySmall?.copyWith(
                            color: onPrimary,
                            fontWeight: FontWeight.bold,
                          ) ??
                          TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: onPrimary,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: textTheme.bodyMedium?.copyWith(
                        color: onPrimary.withValues(alpha: 0.9),
                      ),
                    ),
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
