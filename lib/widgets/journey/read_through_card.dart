import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/badge_award.dart';
import '../../models/lap_coverage.dart';
import '../../models/read_through.dart';
import '../../pages/bible_progress_page.dart';
import '../../pages/read_throughs_page.dart';
import '../../services/badge_service.dart';
import '../../services/coverage_ledger_service.dart';
import '../../services/lap_progress_service.dart';
import '../../services/read_through_service.dart';
import '../../theme/app_theme.dart';
import '../app_bottom_sheet.dart';
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
  final LapProgressService? lapService;

  const ReadThroughCard({
    super.key,
    required this.firestore,
    required this.auth,
    this.service,
    this.coverageService,
    this.badgeService,
    this.lapService,
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
    final laps = lapService ?? LapProgressService(firestore: firestore);

    return StreamBuilder<ReadThroughCounts>(
      stream: coverage.watchCounts(user.uid),
      builder: (context, countsSnapshot) {
        return StreamBuilder<List<BadgeAward>>(
          stream: badges.watch(user.uid),
          builder: (context, badgeSnapshot) {
            return StreamBuilder<LapCoverage>(
              stream: laps.watch(user.uid),
              builder: (context, lapSnapshot) {
                final counts = countsSnapshot.data ?? ReadThroughCounts.empty;
                final awards = badgeSnapshot.data ?? const <BadgeAward>[];
                final loading = countsSnapshot.connectionState ==
                        ConnectionState.waiting ||
                    badgeSnapshot.connectionState == ConnectionState.waiting ||
                    lapSnapshot.connectionState == ConnectionState.waiting;
                return SkeletonLoader(
                  loading: loading,
                  minTime: const Duration(milliseconds: 1000),
                  skeleton: const ReadThroughCardSkeleton(),
                  child: _Card(
                    counts: counts,
                    awards: awards,
                    lap: lapSnapshot.data ?? LapCoverage.empty,
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
      },
    );
  }
}

double _lapFraction(LapCoverage lap, ReadThroughScope scope) =>
    lap.booksComplete(scope) / LapCoverage.booksOf(scope).length;

class _Card extends StatelessWidget {
  final ReadThroughCounts counts;
  final List<BadgeAward> awards;
  final LapCoverage lap;
  final VoidCallback onTap;
  final VoidCallback onOpenLibrary;

  const _Card({
    required this.counts,
    required this.awards,
    required this.lap,
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
                        lapProgress:
                            _lapFraction(lap, ReadThroughScope.oldTestament),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.gap8),
                    Expanded(
                      child: _Count(
                        value: counts.newTestament,
                        label: 'New Testament',
                        lapProgress:
                            _lapFraction(lap, ReadThroughScope.newTestament),
                      ),
                    ),
                  ],
                ),
              ),
              if (counts.wholeBible == 0 &&
                  counts.newTestament == 0 &&
                  counts.oldTestament == 0) ...[
                const SizedBox(height: AppSpacing.gap12),
                Text(
                  'Finish a testament and it lands here.',
                  style: textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: AppSpacing.gap12),
              Divider(height: 1, color: appColors.border),
              _BadgesRow(counts: counts, awards: awards),
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

  /// Share of the current Lap finished, drawn as a thin bar when set.
  final double? lapProgress;

  const _Count({
    required this.value,
    required this.label,
    this.accented = false,
    this.lapProgress,
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
          if (lapProgress != null) ...[
            const SizedBox(height: AppSpacing.gap8),
            Semantics(
              label: 'Current lap ${(lapProgress! * 100).round()} percent',
              excludeSemantics: true,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.rSmall),
                child: LinearProgressIndicator(
                  value: lapProgress,
                  minHeight: 4,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(colorScheme.primary),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Latest and next Badge, with an "All" entry to the read-throughs page.
class _BadgesRow extends StatelessWidget {
  final ReadThroughCounts counts;
  final List<BadgeAward> awards;

  const _BadgesRow({required this.counts, required this.awards});

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
            onPressed: () => showAppSheet<void>(
              context: context,
              fullHeight: true,
              builder: (_) => _AllBadgesSheet(held: held),
            ),
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

/// Every Badge: earned ones filled, the rest dimmed.
class _AllBadgesSheet extends StatelessWidget {
  final Set<String> held;

  const _AllBadgesSheet({required this.held});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.hPadding,
        AppSpacing.gap8,
        AppSpacing.hPadding,
        AppSpacing.gap24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Badges', style: textTheme.titleLarge),
          const SizedBox(height: AppSpacing.gap16),
          Wrap(
            spacing: AppSpacing.gap8,
            runSpacing: AppSpacing.gap16,
            children: [
              for (final badge in BadgeDefinition.all)
                Semantics(
                  label: '${badge.title}, '
                      '${held.contains(badge.id) ? 'earned' : 'not yet earned'}. '
                      '${badge.requirement}',
                  excludeSemantics: true,
                  child: SizedBox(
                    width: 96,
                    child: Opacity(
                      opacity: held.contains(badge.id) ? 1 : 0.45,
                      child: Column(
                        children: [
                          Container(
                            width: 62,
                            height: 62,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: held.contains(badge.id)
                                  ? appColors.primarySoft
                                  : colorScheme.surfaceContainer,
                              border: Border.all(
                                color: held.contains(badge.id)
                                    ? appColors.primaryLine
                                    : appColors.border,
                              ),
                            ),
                            child: Center(
                              child: BadgeGlyph(
                                badge: badge,
                                color: held.contains(badge.id)
                                    ? colorScheme.primary
                                    : colorScheme.outline,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.gap8),
                          Text(
                            badge.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
