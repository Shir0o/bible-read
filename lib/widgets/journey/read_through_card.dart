import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/badge_award.dart';
import '../../models/read_through.dart';
import '../../pages/bible_progress_page.dart';
import '../../pages/read_throughs_page.dart';
import '../../services/badge_service.dart';
import '../../services/coverage_ledger_service.dart';
import '../../services/read_through_service.dart';
import '../../theme/app_theme.dart';
import '../skeleton_loader.dart';
import '../skeletons/read_through_card_skeleton.dart';
import 'badge_glyph.dart';

/// How many times through, on the Journey tab, and the way in to the history.
class ReadThroughCard extends StatelessWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final ReadThroughService? service;
  final CoverageLedgerService? coverageService;
  final BadgeService? badgeService;

  const ReadThroughCard({
    super.key,
    required this.firestore,
    required this.auth,
    this.service,
    this.coverageService,
    this.badgeService,
  });

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    final coverage = coverageService ??
        CoverageLedgerService(
          firestore: firestore,
          readThroughService: service,
        );

    final badges = badgeService ?? BadgeService(firestore: firestore);

    return StreamBuilder<ReadThroughCounts>(
      stream: coverage.watchCounts(user.uid),
      builder: (context, countsSnapshot) {
        return StreamBuilder<List<BadgeAward>>(
          stream: badges.watch(user.uid),
          builder: (context, badgeSnapshot) {
            final counts = countsSnapshot.data ?? ReadThroughCounts.empty;
            final awards = badgeSnapshot.data ?? const <BadgeAward>[];
            final loading =
                countsSnapshot.connectionState == ConnectionState.waiting ||
                    badgeSnapshot.connectionState == ConnectionState.waiting;
            return SkeletonLoader(
              loading: loading,
              minTime: const Duration(milliseconds: 1000),
              skeleton: const ReadThroughCardSkeleton(),
              child: _Card(
                counts: counts,
                awards: awards,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReadThroughsPage(
                      firestore: firestore,
                      auth: auth,
                      service: service,
                    ),
                  ),
                ),
                onOpenLibrary: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BibleProgressPage(
                      firestore: firestore,
                      auth: auth,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  final ReadThroughCounts counts;
  final List<BadgeAward> awards;
  final VoidCallback onTap;
  final VoidCallback onOpenLibrary;

  const _Card({
    required this.counts,
    required this.awards,
    required this.onTap,
    required this.onOpenLibrary,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appColors = AppColors.of(context);

    return Padding(
      padding: AppSpacing.horizontal,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppSpacing.rCard),
            border: Border.all(color: appColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Times through', style: textTheme.titleLarge),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.gap12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _Count(
                        value: counts.wholeBible,
                        label: 'Whole Bible',
                        accented: true,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.gap8),
                    Expanded(
                      child: _Count(
                        value: counts.oldTestament,
                        label: 'Old Testament',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.gap8),
                    Expanded(
                      child: _Count(
                        value: counts.newTestament,
                        label: 'New Testament',
                      ),
                    ),
                  ],
                ),
              ),
              if (counts.wholeBible == 0 &&
                  counts.newTestament == 0 &&
                  counts.oldTestament == 0) ...[
                const SizedBox(height: 12),
                Text(
                  'Finish a testament and it lands here.',
                  style: textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: AppSpacing.gap12),
              Divider(height: 1, color: appColors.border),
              _BadgesRow(counts: counts, awards: awards, onAll: onTap),
              Divider(height: 1, color: appColors.border),
              _LibraryRow(onTap: onOpenLibrary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  final int value;
  final String label;
  final bool accented;

  const _Count({
    required this.value,
    required this.label,
    this.accented = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appColors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gap12, vertical: AppSpacing.gap12),
      decoration: BoxDecoration(
        color:
            accented ? appColors.accentSoft : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.rInset),
        border: Border.all(
          color: accented
              ? colorScheme.tertiary.withValues(alpha: 0.28)
              : appColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: textTheme.headlineSmall?.copyWith(
              height: 1,
              color: accented
                  ? colorScheme.onTertiaryContainer
                  : colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.gap4),
          // One word per line, shrunk rather than broken mid-word when a
          // large text size makes "Testament" wider than the tile.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label.replaceAll(' ', '\n'),
              style: textTheme.bodySmall?.copyWith(
                color: accented
                    ? colorScheme.onTertiaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Latest and next Badge, with an "All" entry to the read-throughs page.
class _BadgesRow extends StatelessWidget {
  final ReadThroughCounts counts;
  final List<BadgeAward> awards;
  final VoidCallback onAll;

  const _BadgesRow({
    required this.counts,
    required this.awards,
    required this.onAll,
  });

  BadgeDefinition? get _latest {
    final dated = awards.where((a) => a.unlockedAt != null).toList()
      ..sort((a, b) => b.unlockedAt!.compareTo(a.unlockedAt!));
    final award = dated.isNotEmpty
        ? dated.first
        : (awards.isNotEmpty ? awards.first : null);
    return award == null ? null : BadgeDefinition.byId(award.id);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final held = awards.map((a) => a.id).toSet();
    final latest = _latest;
    final next = nextBadge(held, counts);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.gap12),
      child: Row(
        children: [
          Expanded(
            child: _BadgeSlot(
              caption: 'Latest badge',
              badge: latest,
              earned: true,
              emptyLabel: 'None yet',
            ),
          ),
          const SizedBox(width: AppSpacing.gap8),
          Expanded(
            child: _BadgeSlot(
              caption: 'Next badge',
              badge: next,
              earned: false,
              emptyLabel: 'All earned',
            ),
          ),
          TextButton(
            onPressed: onAll,
            child: Text(
              'All',
              style: textTheme.labelLarge?.copyWith(color: colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeSlot extends StatelessWidget {
  final String caption;
  final BadgeDefinition? badge;
  final bool earned;
  final String emptyLabel;

  const _BadgeSlot({
    required this.caption,
    required this.badge,
    required this.earned,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appColors = AppColors.of(context);

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                earned ? appColors.primarySoft : colorScheme.surfaceContainer,
            border: Border.all(
              color: earned ? appColors.primaryLine : appColors.border,
            ),
          ),
          child: Center(
            child: badge == null
                ? null
                : BadgeGlyph(
                    badge: badge!,
                    size: 19,
                    color: earned
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
        const SizedBox(width: AppSpacing.gap8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(caption, style: textTheme.labelMedium),
              Text(
                badge?.title ?? emptyLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LibraryRow extends StatelessWidget {
  final VoidCallback onTap;

  const _LibraryRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.gap12),
        child: Row(
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: AppSpacing.iconMd,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.gap12),
            Expanded(child: Text('Library', style: textTheme.titleSmall)),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
