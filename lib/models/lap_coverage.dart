import '../services/reference_parser.dart';
import 'read_through.dart';

/// The chapters a user has marked read in their *current* lap of each
/// testament.
///
/// Distinct from lifetime coverage, which is a union and therefore can only
/// ever grow: re-reading Matthew adds nothing to a set that already holds it.
/// Laps need their own tally, so this is accumulated as the user marks and
/// emptied for a testament when that testament completes.
class LapCoverage {
  /// Chapters read in the current Old Testament lap, by canonical book name.
  final Map<String, Set<int>> oldTestament;

  /// Chapters read in the current New Testament lap, by canonical book name.
  final Map<String, Set<int>> newTestament;

  const LapCoverage({
    required this.oldTestament,
    required this.newTestament,
  });

  static const empty = LapCoverage(oldTestament: {}, newTestament: {});

  /// The 39 books of the Old Testament, in canonical order.
  static List<String> get otBooks =>
      ReferenceParser.allBooks.sublist(0, otBookCount);

  /// The 27 books of the New Testament, in canonical order.
  static List<String> get ntBooks =>
      ReferenceParser.allBooks.sublist(otBookCount);

  /// Genesis through Malachi. The split the app already uses elsewhere.
  static const int otBookCount = 39;

  /// The testament [book] belongs to, or `null` when it is not a Bible book.
  static ReadThroughScope? testamentOf(String book) {
    final index = ReferenceParser.allBooks.indexOf(book);
    if (index < 0) return null;
    return index < otBookCount
        ? ReadThroughScope.oldTestament
        : ReadThroughScope.newTestament;
  }

  Map<String, Set<int>> forScope(ReadThroughScope scope) => switch (scope) {
        ReadThroughScope.oldTestament => oldTestament,
        ReadThroughScope.newTestament => newTestament,
        ReadThroughScope.wholeBible => {...oldTestament, ...newTestament},
      };

  static List<String> booksOf(ReadThroughScope scope) => switch (scope) {
        ReadThroughScope.oldTestament => otBooks,
        ReadThroughScope.newTestament => ntBooks,
        ReadThroughScope.wholeBible => ReferenceParser.allBooks,
      };

  /// Whether every chapter of [book] has been read in the current lap.
  bool isBookComplete(String book) {
    final scope = testamentOf(book);
    if (scope == null) return false;
    final total = ReferenceParser.chapterCount(book) ?? 0;
    if (total <= 0) return false;
    return (forScope(scope)[book] ?? const <int>{}).length >= total;
  }

  /// How many books of [scope] are finished in the current lap.
  int booksComplete(ReadThroughScope scope) =>
      booksOf(scope).where(isBookComplete).length;

  /// Whether the current lap of [scope] covers every book of it.
  bool isComplete(ReadThroughScope scope) {
    final books = booksOf(scope);
    return books.isNotEmpty && booksComplete(scope) == books.length;
  }

  /// A copy with [chapters] (canonical book name to chapter numbers) added to
  /// whichever testament each book belongs to.
  LapCoverage plus(Map<String, Set<int>> chapters) {
    final ot = _copy(oldTestament);
    final nt = _copy(newTestament);
    chapters.forEach((book, added) {
      final scope = testamentOf(book);
      if (scope == null) return;
      final target = scope == ReadThroughScope.oldTestament ? ot : nt;
      target.putIfAbsent(book, () => <int>{}).addAll(added);
    });
    return LapCoverage(oldTestament: ot, newTestament: nt);
  }

  /// A copy with [scope]'s lap emptied, ready to start again.
  LapCoverage cleared(ReadThroughScope scope) => LapCoverage(
        oldTestament:
            scope == ReadThroughScope.oldTestament ? {} : _copy(oldTestament),
        newTestament:
            scope == ReadThroughScope.newTestament ? {} : _copy(newTestament),
      );

  factory LapCoverage.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    return LapCoverage(
      oldTestament: _read(map['ot']),
      newTestament: _read(map['nt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'ot': _write(oldTestament),
        'nt': _write(newTestament),
      };

  static Map<String, Set<int>> _copy(Map<String, Set<int>> source) =>
      source.map((book, chapters) => MapEntry(book, {...chapters}));

  static Map<String, Set<int>> _read(dynamic raw) {
    if (raw is! Map) return {};
    final result = <String, Set<int>>{};
    raw.forEach((book, chapters) {
      if (book is! String || chapters is! List) return;
      result[book] = chapters.whereType<num>().map((n) => n.toInt()).toSet();
    });
    return result;
  }

  static Map<String, List<int>> _write(Map<String, Set<int>> source) {
    final result = <String, List<int>>{};
    source.forEach((book, chapters) {
      if (chapters.isEmpty) return;
      result[book] = chapters.toList()..sort();
    });
    return result;
  }
}
