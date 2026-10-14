import 'package:flutter/material.dart';

import '../models/read_log.dart';
import '../services/milestone_announcer.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_styles.dart';
import 'sun_mark.dart';

class FeedCard extends StatelessWidget {
  final ReadLog log;
  final VoidCallback onToggleLike;

  const FeedCard({
    super.key,
    required this.log,
    required this.onToggleLike,
    this.vibrationService,
  });

  final VibrationService? vibrationService;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLiked = log.liked;
    final milestone = log.milestone;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.rInset),
        side: BorderSide(
          color: milestone != null
              ? colorScheme.tertiary.withValues(alpha: 0.28)
              : colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gap12, AppSpacing.gap16,
            AppSpacing.gap12, AppSpacing.gap12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              log.name,
              style: AppTextStyles.subtitle(context).copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            if (milestone != null) ...[
              _MilestoneBanner(milestone: milestone),
              const SizedBox(height: AppSpacing.gap8),
            ],
            MergeSemantics(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.tertiaryContainer,
                    ),
                    child: Icon(
                      Icons.check,
                      size: AppSpacing.iconSm,
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Read today',
                    style: AppTextStyles.bodySmall(
                      context,
                    ).copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (log.likeNames.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.gap8),
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.favorite,
                      size: 12,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _buildLikeText(log.likeNames),
                      style: AppTextStyles.bodySmall(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: _ActionButton(
                icon: isLiked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: 'Amen',
                color: isLiked
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                backgroundColor: isLiked ? colorScheme.primaryContainer : null,
                isSelected: isLiked,
                onTap: () {
                  (vibrationService ?? const VibrationService()).lightImpact();
                  onToggleLike();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildLikeText(List<String> likeNames) {
    const maxToShow = 2;
    if (likeNames.length <= maxToShow) {
      return likeNames.join(' & ');
    }
    final remaining = likeNames.length - maxToShow;
    final noun = remaining == 1 ? 'other' : 'others';
    return '${likeNames.take(maxToShow).join(', ')} and $remaining $noun';
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final bool? isSelected;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.backgroundColor,
    this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      child: Icon(icon, color: color, size: AppSpacing.iconMd),
    );

    return Semantics(
      button: true,
      enabled: true,
      label: label,
      selected: isSelected,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        child: child,
      ),
    );
  }
}

/// The gold band on a feed card for a reader who finished a read-through
/// today.
class _MilestoneBanner extends StatelessWidget {
  final FeedMilestone milestone;

  const _MilestoneBanner({required this.milestone});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: '${milestone.headline}. ${milestone.detail}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gap12, AppSpacing.gap12,
            AppSpacing.gap12, AppSpacing.gap12),
        decoration: BoxDecoration(
          color: AppColors.of(context).accentSoft,
          borderRadius: BorderRadius.circular(AppSpacing.rChip),
        ),
        child: Row(
          children: [
            const SunMark(size: 36, done: true, borderWidth: 1.5),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    milestone.headline,
                    style: textTheme.titleLarge?.copyWith(height: 1.25),
                  ),
                  const SizedBox(height: AppSpacing.gap4),
                  Text(
                    milestone.detail,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
