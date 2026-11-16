import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/lap_coverage.dart';
import '../../models/read_through.dart';
import '../../pages/bible_progress_page.dart';
import '../../services/coverage_ledger_service.dart';
import '../../services/lap_progress_service.dart';
import '../../services/read_through_service.dart';
import '../../theme/app_theme.dart';
import '../skeleton_loader.dart';
import '../skeletons/read_through_card_skeleton.dart';

/// How many times through, on the Journey tab.
class ReadThroughCard extends StatelessWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final ReadThroughService? service;
  final CoverageLedgerService? coverageService;
  final LapProgressService? lapService;

  const ReadThroughCard({
    super.key,
    required this.firestore,
    required this.auth,
    this.service,
    this.coverageService,
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

    final laps = lapService ?? LapProgressService(firestore: firestore);

    return StreamBuilder<ReadThroughCounts>(
      stream: coverage.watchCounts(user.uid),
      builder: (context, countsSnapshot) {
        return StreamBuilder<LapCoverage>(
          stream: laps.watch(user.uid),
          builder: (context, lapSnapshot) {
            final counts = countsSnapshot.data ?? ReadThroughCounts.empty;
            final loading = countsSnapshot.connectionState ==
                    ConnectionState.waiting ||
                lapSnapshot.connectionState == ConnectionState.waiting;
            return SkeletonLoader(
              loading: loading,
              minTime: const Duration(milliseconds: 1000),
              skeleton: const ReadThroughCardSkeleton(),
              child: _Card(
                counts: counts,
                lap: lapSnapshot.data ?? LapCoverage.empty,
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

double _lapFraction(LapCoverage lap, ReadThroughScope scope) =>
    lap.booksComplete(scope) / LapCoverage.booksOf(scope).length;

class _Card extends StatelessWidget {
  final ReadThroughCounts counts;
  final LapCoverage lap;
  final VoidCallback onOpenLibrary;

  const _Card({
    required this.counts,
    required this.lap,
    required this.onOpenLibrary,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appColors = AppColors.of(context);

    return Padding(
      padding: AppSpacing.horizontal,
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
            Text('Times through', style: textTheme.titleLarge),
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
            _LibraryRow(onTap: onOpenLibrary),
          ],
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
