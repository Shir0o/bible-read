import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/achievement_service.dart';
import '../../services/reference_parser.dart';
import '../../theme/app_theme.dart';
import '../../pages/bible_progress_page.dart';

class BibleLibraryGrid extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  const BibleLibraryGrid({
    super.key,
    required this.firestore,
    required this.auth,
  });

  @override
  State<BibleLibraryGrid> createState() => _BibleLibraryGridState();
}

class _BibleLibraryGridState extends State<BibleLibraryGrid> {
  late final AchievementService _achievementService;
  late Stream<Set<String>> _unlockedIdsStream;

  @override
  void initState() {
    super.initState();
    _achievementService = AchievementService(firestore: widget.firestore);
    final user = widget.auth.currentUser;
    if (user != null) {
      _unlockedIdsStream = _achievementService.unlockedAchievementIds(user.uid);
    } else {
      _unlockedIdsStream = Stream.value({});
    }
  }

  String _getAbbreviation(String book) {
    // Custom abbreviations to match design style (3-4 chars)
    switch (book) {
      case 'Genesis': return 'Gen';
      case 'Exodus': return 'Exo';
      case 'Leviticus': return 'Lev';
      case 'Numbers': return 'Num';
      case 'Deuteronomy': return 'Deu';
      case 'Joshua': return 'Jos';
      case 'Judges': return 'Jud';
      case 'Ruth': return 'Rut';
      case '1 Samuel': return '1Sa';
      case '2 Samuel': return '2Sa';
      case '1 Kings': return '1Ki';
      case '2 Kings': return '2Ki';
      case '1 Chronicles': return '1Ch';
      case '2 Chronicles': return '2Ch';
      case 'Ezra': return 'Ezr';
      case 'Nehemiah': return 'Neh';
      case 'Esther': return 'Est';
      case 'Job': return 'Job';
      case 'Psalm': return 'Psa';
      case 'Proverbs': return 'Pro';
      case 'Ecclesiastes': return 'Ecc';
      case 'Song of Songs': return 'Son';
      case 'Isaiah': return 'Isa';
      case 'Jeremiah': return 'Jer';
      case 'Lamentations': return 'Lam';
      case 'Ezekiel': return 'Eze';
      case 'Daniel': return 'Dan';
      case 'Hosea': return 'Hos';
      case 'Joel': return 'Joe';
      case 'Amos': return 'Amo';
      case 'Obadiah': return 'Oba';
      case 'Jonah': return 'Jon';
      case 'Micah': return 'Mic';
      case 'Nahum': return 'Nah';
      case 'Habakkuk': return 'Hab';
      case 'Zephaniah': return 'Zep';
      case 'Haggai': return 'Hag';
      case 'Zechariah': return 'Zec';
      case 'Malachi': return 'Mal';
      case 'Matthew': return 'Mat';
      case 'Mark': return 'Mar';
      case 'Luke': return 'Luk';
      case 'John': return 'Joh';
      case 'Acts': return 'Act';
      case 'Romans': return 'Rom';
      case '1 Corinthians': return '1Co';
      case '2 Corinthians': return '2Co';
      case 'Galatians': return 'Gal';
      case 'Ephesians': return 'Eph';
      case 'Philippians': return 'Phi';
      case 'Colossians': return 'Col';
      case '1 Thessalonians': return '1Th';
      case '2 Thessalonians': return '2Th';
      case '1 Timothy': return '1Ti';
      case '2 Timothy': return '2Ti';
      case 'Titus': return 'Tit';
      case 'Philemon': return 'Phm';
      case 'Hebrews': return 'Heb';
      case 'James': return 'Jam';
      case '1 Peter': return '1Pe';
      case '2 Peter': return '2Pe';
      case '1 John': return '1Jo';
      case '2 John': return '2Jo';
      case '3 John': return '3Jo';
      case 'Jude': return 'Jud';
      case 'Revelation': return 'Rev';
      default: return book.substring(0, 3);
    }
  }

  // Helper to categorize books for coloring (Pentateuch, History, etc.)
  // Simplification: Pentateuch (Gen-Deu) gets a special color in design?
  // Design shows Gen/Exo purple, Lev/Num/Deu gray (hover state?).
  // For now, I'll stick to a base color and highlight "read" ones.
  // Or maybe "completed" ones are colored, others are gray?

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.hPadding),
      child: Column(
        children: [
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
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BibleProgressPage(
                        firestore: widget.firestore,
                        auth: widget.auth,
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
          StreamBuilder<Set<String>>(
            stream: _unlockedIdsStream,
            builder: (context, snapshot) {
              // We'll show a grid of the first N books or all books?
              // Design shows 2 rows of 4 = 8 items. "See All" implies truncated list.
              // I'll show the first 8-12 books or maybe just a horizontal scroll?
              // The design is a GridView. I'll show 8 items (first 8 books of Bible).

              final booksToShow = ReferenceParser.allBooks.take(8).toList();

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.0,
                ),
                itemCount: booksToShow.length,
                itemBuilder: (context, index) {
                  final book = booksToShow[index];
                  final abbr = _getAbbreviation(book);

                  // Design has different colors.
                  // Gen/Exo/Jos are Purple (primary container).
                  // Others gray (surface container).
                  // Maybe it's random or fixed?
                  // I'll alternate or use unlocked status.
                  // Let's assume unlocked = primary color?
                  // Or maybe specific books have specific colors.
                  // For now, I'll use a subtle variation.

                  // If we use index for variety:
                  final isHighlighted = index % 5 == 0 || index == 1;

                  return Container(
                    decoration: BoxDecoration(
                      color: isHighlighted
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isHighlighted
                             ? colorScheme.primary.withValues(alpha: 0.2)
                             : colorScheme.outlineVariant.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.book, // material-symbols: book_2
                          color: isHighlighted
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          abbr,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isHighlighted
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
