import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

import '../models/lap_coverage.dart';
import '../models/read_through.dart';
import '../services/bible_progress_service.dart';
import '../services/lap_progress_service.dart';
import '../services/read_through_service.dart';
import '../services/reference_parser.dart';
import '../services/error_logger.dart';
import '../services/vibration_service.dart';
import '../widgets/dashed_border.dart';
import '../widgets/sub_header.dart';
import 'dart:async';

class BibleProgressPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final String? initialScrollToBook;
  final VibrationService vibrationService;

  const BibleProgressPage({
    super.key,
    required this.firestore,
    required this.auth,
    this.initialScrollToBook,
    this.vibrationService = const VibrationService(),
  });

  @override
  State<BibleProgressPage> createState() => BibleProgressPageState();
}

class BibleProgressPageState extends State<BibleProgressPage> {
  late final BibleProgressService _bibleProgressService;
  late final LapProgressService _lapService;
  late final ReadThroughService _readThroughService;

  // Chapters read in the CURRENT lap — what the grid fills in.
  LapCoverage _lapCoverage = LapCoverage.empty;

  // Everything ever read, used only to mark books an earlier lap covered.
  Map<String, Set<int>> _currentData = {};

  ReadThroughCounts _counts = ReadThroughCounts.empty;
  bool _hasScrolled = false;

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _bookKeys = {};

  // Optimistic UI overrides: bookName -> isCompleted
  final Map<String, bool> _localOverrides = {};

  static const List<MapEntry<String, List<String>>> _categories = [
    MapEntry('Pentateuch', [
      'Genesis',
      'Exodus',
      'Leviticus',
      'Numbers',
      'Deuteronomy',
    ]),
    MapEntry('History', [
      'Joshua',
      'Judges',
      'Ruth',
      '1 Samuel',
      '2 Samuel',
      '1 Kings',
      '2 Kings',
      '1 Chronicles',
      '2 Chronicles',
      'Ezra',
      'Nehemiah',
      'Esther',
    ]),
    MapEntry('Poetry', [
      'Job',
      'Psalm',
      'Proverbs',
      'Ecclesiastes',
      'Song of Songs',
    ]),
    MapEntry('Prophecy', [
      'Isaiah',
      'Jeremiah',
      'Lamentations',
      'Ezekiel',
      'Daniel',
      'Hosea',
      'Joel',
      'Amos',
      'Obadiah',
      'Jonah',
      'Micah',
      'Nahum',
      'Habakkuk',
      'Zephaniah',
      'Haggai',
      'Zechariah',
      'Malachi',
    ]),
    MapEntry('Gospels & Acts', ['Matthew', 'Mark', 'Luke', 'John', 'Acts']),
    MapEntry('Epistles', [
      'Romans',
      '1 Corinthians',
      '2 Corinthians',
      'Galatians',
      'Ephesians',
      'Philippians',
      'Colossians',
      '1 Thessalonians',
      '2 Thessalonians',
      '1 Timothy',
      '2 Timothy',
      'Titus',
      'Philemon',
      'Hebrews',
      'James',
      '1 Peter',
      '2 Peter',
      '1 John',
      '2 John',
      '3 John',
      'Jude',
    ]),
    MapEntry('Prophecy', ['Revelation']),
  ];

  @override
  void initState() {
    super.initState();
    _bibleProgressService = BibleProgressService(firestore: widget.firestore);
    _readThroughService = ReadThroughService(firestore: widget.firestore);
    _lapService = LapProgressService(
      firestore: widget.firestore,
      readThroughService: _readThroughService,
    );
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final user = widget.auth.currentUser;
    if (user == null) {
      return;
    }

    try {
      final data =
          await _bibleProgressService.completedChaptersByBook(user.uid);

      // Carry existing progress into the lap model the first time this user
      // sees a lap-scoped grid. Idempotent, and it matters here as well as in
      // ReadThroughHost: without it the whole library would render as
      // "earlier lap" for anyone whose lap state has not been written yet.
      if (!await _lapService.isSeeded(user.uid)) {
        await _lapService.seedFromLifetime(user.uid, data);
      }

      final results = await Future.wait([
        _lapService.fetch(user.uid),
        _readThroughService.fetchAll(user.uid),
      ]);
      final coverage = results[0] as LapCoverage;
      final ledger = results[1] as List<ReadThrough>;
      if (mounted) {
        setState(() {
          _currentData = data;
          _lapCoverage = coverage;
          _counts = ReadThroughService.countsFrom(ledger);
        });

        // Trigger scroll logic
        final String? targetBook = widget.initialScrollToBook ??
            await _bibleProgressService.getLastCheckedBook(user.uid);

        if (targetBook != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBook(targetBook);
          });
        }
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  void _scrollToBook(String book) {
    if (_hasScrolled) return;
    final key = _bookKeys[book];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        alignment: 0.5, // Center the item
      );
      _hasScrolled = true;
    }
  }

  Map<String, Set<int>> _withOverrides(Map<String, Set<int>> base) {
    if (_localOverrides.isEmpty) return base;

    final Map<String, Set<int>> merged = Map.from(base);
    _localOverrides.forEach((book, isCompleted) {
      if (isCompleted) {
        final count = ReferenceParser.chapterCount(book) ?? 0;
        merged[book] = Set.from(List.generate(count, (i) => i + 1));
      } else {
        merged.remove(book);
      }
    });
    return merged;
  }

  /// What the grid fills in: chapters read in the *current* lap.
  Map<String, Set<int>> _getDisplayData() => _withOverrides({
        ..._lapCoverage.oldTestament,
        ..._lapCoverage.newTestament,
      });

  /// Whether a book was finished in an earlier lap. Those tiles stay visible,
  /// dashed, so starting a lap over never looks like losing progress.
  bool _readInEarlierLap(String book, Map<String, Set<int>> thisLap) {
    if (_isComplete(book, thisLap)) return false;
    return _isComplete(book, _currentData);
  }

  static bool _isComplete(String book, Map<String, Set<int>> data) {
    final total = ReferenceParser.chapterCount(book) ?? 0;
    if (total <= 0) return false;
    return (data[book] ?? const <int>{}).length >= total;
  }

  Future<void> handleBookTap(String book, bool isCurrentlyCompleted) async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    final bool desiredCompleted = !isCurrentlyCompleted;

    if (isCurrentlyCompleted) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierColor: AppColors.of(context).scrim,
        builder: (context) => AlertDialog.adaptive(
          title: Text('Mark $book as unread?'),
          content: Text('This will remove the manual completion for $book.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierColor: AppColors.of(context).scrim,
        builder: (context) => AlertDialog.adaptive(
          title: Text('Complete $book?'),
          content: Text('Mark $book as read?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    // 1. Apply Optimistic Update
    unawaited(widget.vibrationService.lightImpact());
    setState(() {
      _localOverrides[book] = desiredCompleted;
    });

    try {
      if (desiredCompleted) {
        await widget.firestore
            .collection('users')
            .doc(user.uid)
            .collection('bible_books')
            .doc(book)
            .set({
          'completed': true,
          'timestamp': FieldValue.serverTimestamp(),
        });

        // Marking a book by hand counts toward the current lap, exactly as
        // checking its chapters off in a group or a plan would.
        final total = ReferenceParser.chapterCount(book) ?? 0;
        if (total > 0) {
          await _lapService.recordChapters(
            user.uid,
            List<String>.generate(total, (i) => '$book ${i + 1}'),
          );
          await _loadData();
        }
      } else {
        await widget.firestore
            .collection('users')
            .doc(user.uid)
            .collection('bible_books')
            .doc(book)
            .delete();
      }

      // Successfully updated, we can eventually clear override but
      // keeping it is safe until next full reload.
    } catch (e, st) {
      // 2. Rollback on failure
      setState(() {
        _localOverrides.remove(book);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update $book. Please try again.')),
        );
      }
      ErrorLogger.log(e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final completedData = _getDisplayData();

    var completedBooks = 0;
    for (final entry in _categories) {
      for (final book in entry.value) {
        if (_isComplete(book, completedData)) {
          completedBooks++;
        }
      }
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            SubHeader(
              title: 'Bible Library',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: _LapBanner(
                      counts: _counts,
                      booksThisLap: completedBooks,
                    ),
                  ),
                  const SliverToBoxAdapter(child: _LapLegend()),
                  for (final entry in _categories) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Text(
                                entry.key.toUpperCase(),
                                style: textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 9,
                          crossAxisSpacing: 9,
                          childAspectRatio: 1.35,
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final book = entry.value[index];
                          final isCompleted = _isComplete(book, completedData);
                          final earlier =
                              _readInEarlierLap(book, completedData);

                          final key = _bookKeys.putIfAbsent(
                            book,
                            () => GlobalKey(),
                          );

                          return _BookGridItem(
                            key: key,
                            book: book,
                            isUnlocked: isCompleted,
                            readInEarlierLap: earlier,
                            onTap: () => handleBookTap(book, isCompleted),
                          );
                        }, childCount: entry.value.length),
                      ),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: Text(
                        '$completedBooks of 66 books this lap. '
                        'Read in your own Bible — mark books as you go.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookGridItem extends StatelessWidget {
  final String book;

  /// Finished in the current lap.
  final bool isUnlocked;

  /// Finished in an earlier lap, but not yet in this one.
  final bool readInEarlierLap;

  final VoidCallback onTap;

  const _BookGridItem({
    super.key,
    required this.book,
    required this.isUnlocked,
    required this.onTap,
    this.readInEarlierLap = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);

    final Color background = isUnlocked
        ? appColors.primarySoft
        : readInEarlierLap
            ? colorScheme.surfaceContainer
            : colorScheme.surfaceContainer;
    final Color ink = isUnlocked
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant.withValues(
            alpha: readInEarlierLap ? 0.75 : 1.0,
          );

    final String status = isUnlocked
        ? 'Read this lap'
        : readInEarlierLap
            ? 'Read in an earlier lap'
            : 'Not read yet';

    Widget tile = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        // An earlier lap gets its border painted dashed on top instead.
        border: readInEarlierLap
            ? null
            : Border.all(
                color: isUnlocked ? appColors.primaryLine : appColors.border,
              ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book_rounded,
            size: 18,
            color: isUnlocked
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withValues(
                    alpha: readInEarlierLap ? 0.55 : 0.7,
                  ),
          ),
          const SizedBox(height: 7),
          Text(
            book,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ],
      ),
    );

    if (readInEarlierLap) {
      tile = CustomPaint(
        foregroundPainter: DashedRoundedBorderPainter(
          color: appColors.borderStrong,
        ),
        child: tile,
      );
    }

    return RepaintBoundary(
      child: Tooltip(
        message: '$book ($status)',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Semantics(
            label: '$book, $status',
            button: true,
            excludeSemantics: true,
            child: tile,
          ),
        ),
      ),
    );
  }
}

/// Says which lap the reader is on, so a grid that just emptied itself reads as
/// a fresh start rather than lost progress.
class _LapBanner extends StatelessWidget {
  final ReadThroughCounts counts;
  final int booksThisLap;

  const _LapBanner({required this.counts, required this.booksThisLap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appColors = AppColors.of(context);

    final bibles = counts.wholeBible;
    final progress = booksThisLap / 66;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.rCard),
          border: Border.all(color: appColors.border),
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
                        'OLD TESTAMENT LAP '
                        '${counts.currentLap(ReadThroughScope.oldTestament)}'
                        '  ·  NEW TESTAMENT LAP '
                        '${counts.currentLap(ReadThroughScope.newTestament)}',
                        style: textTheme.labelSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        bibles == 0
                            ? 'Working through it'
                            : bibles == 1
                                ? 'Been all the way through once'
                                : 'Been all the way through $bibles times',
                        style: textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$booksThisLap',
                      style: textTheme.titleLarge?.copyWith(
                        height: 1,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('of 66 books', style: textTheme.bodySmall),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 16,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explains the two tile styles in the grid.
class _LapLegend extends StatelessWidget {
  const _LapLegend();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    Widget key(Widget swatch, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            swatch,
            const SizedBox(width: 7),
            Text(label, style: textTheme.bodySmall),
          ],
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          key(
            Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: appColors.primarySoft,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: appColors.primaryLine),
              ),
            ),
            'Read this lap',
          ),
          const SizedBox(width: 16),
          key(
            CustomPaint(
              foregroundPainter: DashedRoundedBorderPainter(
                color: appColors.borderStrong,
                radius: 4,
                dashLength: 2,
                gapLength: 2,
              ),
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            'Read in an earlier lap',
          ),
        ],
      ),
    );
  }
}
