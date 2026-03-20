import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/bible_progress_service.dart';
import '../services/reference_parser.dart';
import '../services/error_logger.dart';

class BibleProgressPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final String? initialScrollToBook;

  const BibleProgressPage({
    super.key,
    required this.firestore,
    required this.auth,
    this.initialScrollToBook,
  });

  @override
  State<BibleProgressPage> createState() => _BibleProgressPageState();
}

class _BibleProgressPageState extends State<BibleProgressPage> {
  late final BibleProgressService _bibleProgressService;
  
  // The synchronous source of truth for the UI
  Map<String, Set<int>> _currentData = {};
  bool _loading = true;
  bool _hasScrolled = false;

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _bookKeys = {};

  // Optimistic UI overrides: bookName -> isCompleted
  final Map<String, bool> _localOverrides = {};

  static const List<MapEntry<String, List<String>>> _categories = [
    MapEntry('Pentateuch',
        ['Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy']),
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
      'Esther'
    ]),
    MapEntry('Poetry',
        ['Job', 'Psalm', 'Proverbs', 'Ecclesiastes', 'Song of Songs']),
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
      'Malachi'
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
      'Jude'
    ]),
    MapEntry('Prophecy', ['Revelation']),
  ];

  @override
  void initState() {
    super.initState();
    _bibleProgressService =
        BibleProgressService(firestore: widget.firestore);
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
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final data = await _bibleProgressService.completedChaptersByBook(user.uid);
      if (mounted) {
        setState(() {
          _currentData = data;
          _loading = false;
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
      if (mounted) setState(() => _loading = false);
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

  Future<void> _handleBookTap(String book, bool isCurrentlyCompleted) async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    final bool desiredCompleted = !isCurrentlyCompleted;

    if (isCurrentlyCompleted) {
      final confirmed = await showDialog<bool>(
        context: context,
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

  String _getAbbreviation(String book) {
    switch (book) {
      case 'Genesis':
        return 'Gen';
      case 'Exodus':
        return 'Exo';
      case 'Leviticus':
        return 'Lev';
      case 'Numbers':
        return 'Num';
      case 'Deuteronomy':
        return 'Deu';
      case 'Joshua':
        return 'Jos';
      case 'Judges':
        return 'Jud';
      case 'Ruth':
        return 'Rut';
      case '1 Samuel':
        return '1Sa';
      case '2 Samuel':
        return '2Sa';
      case '1 Kings':
        return '1Ki';
      case '2 Kings':
        return '2Ki';
      case '1 Chronicles':
        return '1Ch';
      case '2 Chronicles':
        return '2Ch';
      case 'Ezra':
        return 'Ezr';
      case 'Nehemiah':
        return 'Neh';
      case 'Esther':
        return 'Est';
      case 'Job':
        return 'Job';
      case 'Psalm':
        return 'Psa';
      case 'Proverbs':
        return 'Pro';
      case 'Ecclesiastes':
        return 'Ecc';
      case 'Song of Songs':
        return 'Sol';
      case 'Isaiah':
        return 'Isa';
      case 'Jeremiah':
        return 'Jer';
      case 'Lamentations':
        return 'Lam';
      case 'Ezekiel':
        return 'Eze';
      case 'Daniel':
        return 'Dan';
      case 'Hosea':
        return 'Hos';
      case 'Joel':
        return 'Joe';
      case 'Amos':
        return 'Amo';
      case 'Obadiah':
        return 'Oba';
      case 'Jonah':
        return 'Jon';
      case 'Micah':
        return 'Mic';
      case 'Nahum':
        return 'Nah';
      case 'Habakkuk':
        return 'Hab';
      case 'Zephaniah':
        return 'Zep';
      case 'Haggai':
        return 'Hag';
      case 'Zechariah':
        return 'Zec';
      case 'Malachi':
        return 'Mal';
      case 'Matthew':
        return 'Mat';
      case 'Mark':
        return 'Mar';
      case 'Luke':
        return 'Luk';
      case 'John':
        return 'Joh';
      case 'Acts':
        return 'Act';
      case 'Romans':
        return 'Rom';
      case '1 Corinthians':
        return '1Co';
      case '2 Corinthians':
        return '2Co';
      case 'Galatians':
        return 'Gal';
      case 'Ephesians':
        return 'Eph';
      case 'Philippians':
        return 'Phi';
      case 'Colossians':
        return 'Col';
      case '1 Thessalonians':
        return '1Th';
      case '2 Thessalonians':
        return '2Th';
      case '1 Timothy':
        return '1Ti';
      case '2 Timothy':
        return '2Ti';
      case 'Titus':
        return 'Tit';
      case 'Philemon':
        return 'Phm';
      case 'Hebrews':
        return 'Heb';
      case 'James':
        return 'Jam';
      case '1 Peter':
        return '1Pe';
      case '2 Peter':
        return '2Pe';
      case '1 John':
        return '1Jo';
      case '2 John':
        return '2Jo';
      case '3 John':
        return '3Jo';
      case 'Jude':
        return 'Jud';
      case 'Revelation':
        return 'Rev';
      default:
        return book.substring(0, 3);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Progress')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final completedData = _getDisplayData();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Library',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              'Progress',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: CustomScrollView(
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
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.5))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
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
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.5))),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.0,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final book = entry.value[index];
                    final chapters = completedData[book] ?? {};
                    final totalChapters =
                        ReferenceParser.chapterCount(book) ?? 0;
                    final isCompleted =
                        totalChapters > 0 && chapters.length >= totalChapters;
                    final abbr = _getAbbreviation(book);

                    final key = _bookKeys.putIfAbsent(book, () => GlobalKey());

                    return _BookGridItem(
                      key: key,
                      book: book,
                      abbr: abbr,
                      isUnlocked: isCompleted,
                      onTap: () => _handleBookTap(book, isCompleted),
                    );
                  },
                  childCount: entry.value.length,
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

class _BookGridItem extends StatelessWidget {
  final String book;
  final String abbr;
  final bool isUnlocked;
  final VoidCallback onTap;

  const _BookGridItem({
    super.key,
    required this.book,
    required this.abbr,
    required this.isUnlocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: Tooltip(
        message: isUnlocked ? '$book (Completed)' : book,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Semantics(
            label: '$book, ${isUnlocked ? "Completed" : "Not completed"}',
            button: true,
            excludeSemantics: true,
            child: Container(
              decoration: BoxDecoration(
                color: isUnlocked ? colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: isUnlocked
                    ? null
                    : Border.all(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                boxShadow: isUnlocked
                    ? [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (isUnlocked)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(
                        Icons.check,
                        size: 14,
                        color: colorScheme.onPrimary,
                        weight: 700, // bold
                      ),
                    ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.menu_book_rounded, // or book_2
                        color: isUnlocked
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant,
                        size: 24,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        abbr,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isUnlocked
                              ? colorScheme.onPrimary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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
