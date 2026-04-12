import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/bible_progress_service.dart';
import '../../services/reference_parser.dart';
import '../../theme/app_theme.dart';
import '../../pages/bible_progress_page.dart';
import '../../widgets/skeletons/bible_library_grid_skeleton.dart';
import '../skeleton_loader.dart';

import '../../services/vibration_service.dart';

class BibleLibraryGrid extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final Map<String, Set<int>>? initialCompletedByBook;
  final bool showTitle;
  final bool isLoading;
  final VibrationService vibrationService;

  const BibleLibraryGrid({
    super.key,
    required this.firestore,
    required this.auth,
    this.initialCompletedByBook,
    this.showTitle = true,
    this.isLoading = false,
    this.vibrationService = const VibrationService(),
  });

  @override
  State<BibleLibraryGrid> createState() => _BibleLibraryGridState();
}

class _BibleLibraryGridState extends State<BibleLibraryGrid> {
  late final BibleProgressService _bibleProgressService;
  late Stream<Map<String, Set<int>>> _completedStream;

  @override
  void initState() {
    super.initState();
    _bibleProgressService = BibleProgressService(firestore: widget.firestore);
    final user = widget.auth.currentUser;
    if (user != null) {
      _completedStream = widget.initialCompletedByBook != null
          ? Stream.value(widget.initialCompletedByBook!)
          : Stream.fromFuture(
              _bibleProgressService.completedChaptersByBook(user.uid));
    } else {
      _completedStream = Stream.value({});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.hPadding),
      child: Column(
        children: [
          if (widget.showTitle) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Bible Library',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                ),
                TextButton(
                  onPressed: () {
                    unawaited(widget.vibrationService.lightImpact());
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BibleProgressPage(
                          firestore: widget.firestore,
                          auth: widget.auth,
                          vibrationService: widget.vibrationService,
                        ),
                      ),
                    );
                  },
                  child: Text(
                    'See All',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          SkeletonLoader(
            loading: widget.isLoading,
            minTime: const Duration(milliseconds: 1000),
            skeleton: const BibleLibraryGridSkeleton(),
            child: StreamBuilder<Map<String, Set<int>>>(
              stream: _completedStream,
              builder: (context, snapshot) {
                final completedData = snapshot.data ?? {};

                // Calculate metrics
                int completedBooksCount = 0;
                int otCompleted = 0;
                int ntCompleted = 0;

                for (final book in ReferenceParser.allBooks) {
                  final chapters = completedData[book] ?? {};
                  final totalChapters = ReferenceParser.chapterCount(book) ?? 0;

                  if (totalChapters > 0 && chapters.length >= totalChapters) {
                    completedBooksCount++;
                    // The first 39 books are OT, the rest NT
                    if (ReferenceParser.allBooks.indexOf(book) < 39) {
                      otCompleted++;
                    } else {
                      ntCompleted++;
                    }
                  }
                }

                final totalBooks = ReferenceParser.allBooks.length;
                final overallProgress =
                    totalBooks > 0 ? completedBooksCount / totalBooks : 0.0;
                final overallPercentText =
                    '${(overallProgress * 100).toInt()}%';

                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Overall Progress',
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      overallPercentText,
                                      style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                        height: 1.0,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Done',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$completedBooksCount',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'of $totalBooks Books',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Custom Progress Bar
                      Container(
                        height: 16,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          children: [
                            FractionallySizedBox(
                              widthFactor: overallProgress.clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            // Optional partition line
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              child: Row(
                                children: [
                                  // Approximate OT ratio is 39/66 ~ 59%
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      // Constraints aren't useful here in a free-floating position.
                                      // A simpler approach is leaving it un-partitioned for now or calculating width
                                      // via a Flex layout instead of Stack. Let's keep it simple as a solid bar.
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Row for OT and NT
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: colorScheme.outlineVariant
                                      .withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.menu_book,
                                      color: colorScheme.onPrimaryContainer,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'OLD TESTAMENT',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$otCompleted/39',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onSurface,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: colorScheme.outlineVariant
                                      .withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: colorScheme.secondaryContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.auto_stories,
                                      color: colorScheme.onSecondaryContainer,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'NEW TESTAMENT',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$ntCompleted/27',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onSurface,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
