import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

import '../services/bible_progress_service.dart';
import '../services/reference_parser.dart';
import '../services/error_logger.dart';
import '../services/vibration_service.dart';
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

  // The synchronous source of truth for the UI
  Map<String, Set<int>> _currentData = {};
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
      final data = await _bibleProgressService.completedChaptersByBook(
        user.uid,
      );
      if (mounted) {
        setState(() {
          _currentData = data;
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

  Map<String, Set<int>> _getDisplayData() {
    if (_localOverrides.isEmpty) return _currentData;

    final Map<String, Set<int>> merged = Map.from(_currentData);
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

        // Award 'New Testament Starter' badge if this is the first book completed
        final booksSnap = await widget.firestore
            .collection('users')
            .doc(user.uid)
            .collection('bible_books')
            .get();

        if (booksSnap.docs.length == 1) {
          await widget.firestore
              .collection('users')
              .doc(user.uid)
              .collection('achievements')
              .doc('nt_starter')
              .set({
            'title': 'NT Starter',
            'type': 'achievement',
            'dateUnlocked': FieldValue.serverTimestamp(),
          });
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
        final chapters = completedData[book] ?? const <int>{};
        final totalChapters = ReferenceParser.chapterCount(book) ?? 0;
        if (totalChapters > 0 && chapters.length >= totalChapters) {
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
                          final chapters = completedData[book] ?? {};
                          final totalChapters =
                              ReferenceParser.chapterCount(book) ?? 0;
                          final isCompleted = totalChapters > 0 &&
                              chapters.length >= totalChapters;

                          final key = _bookKeys.putIfAbsent(
                            book,
                            () => GlobalKey(),
                          );

                          return _BookGridItem(
                            key: key,
                            book: book,
                            isUnlocked: isCompleted,
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
                        '$completedBooks of 66 books completed. '
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
  final bool isUnlocked;
  final VoidCallback onTap;

  const _BookGridItem({
    super.key,
    required this.book,
    required this.isUnlocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);

    return RepaintBoundary(
      child: Tooltip(
        message: isUnlocked ? '$book (Completed)' : book,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Semantics(
            label: '$book, ${isUnlocked ? "Completed" : "Not completed"}',
            button: true,
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              decoration: BoxDecoration(
                color: isUnlocked
                    ? appColors.primarySoft
                    : colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
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
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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
                      color: isUnlocked
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
