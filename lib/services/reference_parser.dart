/// Normalizes user-entered Bible chapter references into a consistent
/// "Book Chapter" format (e.g. "John 3").
class ReferenceParser {
  ReferenceParser._();

  /// Maps canonicalized book keys to standardized display names.
  /// Keys are lowercase and stripped of spaces/punctuation.
  static const Map<String, String> _bookMap = {
    // Pentateuch
    'genesis': 'Genesis', 'gen': 'Genesis', 'ge': 'Genesis', 'gn': 'Genesis',
    'exodus': 'Exodus', 'exo': 'Exodus', 'ex': 'Exodus',
    'leviticus': 'Leviticus', 'lev': 'Leviticus', 'lv': 'Leviticus',
    'numbers': 'Numbers', 'num': 'Numbers', 'nu': 'Numbers', 'nm': 'Numbers',
    'deuteronomy': 'Deuteronomy', 'deut': 'Deuteronomy', 'deu': 'Deuteronomy',
    'dt': 'Deuteronomy',

    // History
    'joshua': 'Joshua', 'josh': 'Joshua', 'jos': 'Joshua',
    'judges': 'Judges', 'judg': 'Judges', 'jdg': 'Judges',
    'ruth': 'Ruth', 'rut': 'Ruth',
    'samuel': 'Samuel', 'sam': 'Samuel',
    'kings': 'Kings', 'kgs': 'Kings', 'king': 'Kings',
    'chronicles': 'Chronicles', 'chron': 'Chronicles', 'chr': 'Chronicles',
    'ch': 'Chronicles',
    'ezra': 'Ezra',
    'nehemiah': 'Nehemiah', 'neh': 'Nehemiah',
    'esther': 'Esther', 'est': 'Esther',

    // Wisdom
    'job': 'Job',
    'psalm': 'Psalm', 'psalms': 'Psalm', 'ps': 'Psalm', 'psa': 'Psalm',
    'psm': 'Psalm',
    'proverbs': 'Proverbs', 'prov': 'Proverbs', 'pr': 'Proverbs',
    'prv': 'Proverbs',
    'ecclesiastes': 'Ecclesiastes', 'eccl': 'Ecclesiastes',
    'ecc': 'Ecclesiastes', 'qoheleth': 'Ecclesiastes',
    'songofsongs': 'Song of Songs',
    'songofsolomon': 'Song of Songs',
    'songs': 'Song of Songs',
    'song': 'Song of Songs',
    'sos': 'Song of Songs',
    'canticles': 'Song of Songs',

    // Major prophets
    'isaiah': 'Isaiah', 'isa': 'Isaiah',
    'jeremiah': 'Jeremiah', 'jer': 'Jeremiah',
    'lamentations': 'Lamentations', 'lam': 'Lamentations',
    'ezekiel': 'Ezekiel', 'ezek': 'Ezekiel', 'ezk': 'Ezekiel',
    'daniel': 'Daniel', 'dan': 'Daniel', 'dn': 'Daniel',

    // Minor prophets
    'hosea': 'Hosea', 'hos': 'Hosea',
    'joel': 'Joel',
    'amos': 'Amos',
    'obadiah': 'Obadiah', 'oba': 'Obadiah', 'ob': 'Obadiah',
    'jonah': 'Jonah', 'jon': 'Jonah',
    'micah': 'Micah', 'mic': 'Micah',
    'nahum': 'Nahum', 'nah': 'Nahum',
    'habakkuk': 'Habakkuk', 'hab': 'Habakkuk',
    'zephaniah': 'Zephaniah', 'zep': 'Zephaniah', 'zeph': 'Zephaniah',
    'haggai': 'Haggai', 'hag': 'Haggai',
    'zechariah': 'Zechariah', 'zec': 'Zechariah', 'zech': 'Zechariah',
    'malachi': 'Malachi', 'mal': 'Malachi',

    // Gospels & Acts
    'matthew': 'Matthew', 'matt': 'Matthew', 'mat': 'Matthew', 'mt': 'Matthew',
    'mark': 'Mark', 'mk': 'Mark',
    'luke': 'Luke', 'luk': 'Luke', 'lk': 'Luke',
    'john': 'John', 'jhn': 'John', 'joh': 'John', 'jn': 'John',
    'acts': 'Acts', 'act': 'Acts', 'ac': 'Acts',

    // Paul & general epistles
    'romans': 'Romans', 'rom': 'Romans',
    'corinthians': 'Corinthians', 'cor': 'Corinthians',
    'galatians': 'Galatians', 'gal': 'Galatians',
    'ephesians': 'Ephesians', 'eph': 'Ephesians',
    'philippians': 'Philippians', 'phil': 'Philippians', 'php': 'Philippians',
    'phi': 'Philippians',
    'colossians': 'Colossians', 'col': 'Colossians',
    'thessalonians': 'Thessalonians', 'thess': 'Thessalonians',
    'thes': 'Thessalonians', 'ths': 'Thessalonians',
    'timothy': 'Timothy', 'tim': 'Timothy',
    'titus': 'Titus', 'tit': 'Titus',
    'philemon': 'Philemon', 'philem': 'Philemon', 'phm': 'Philemon',
    'hebrews': 'Hebrews', 'heb': 'Hebrews',
    'james': 'James', 'jas': 'James', 'jam': 'James',
    'peter': 'Peter', 'pet': 'Peter', 'ptr': 'Peter',
    // Note: 1 John/2 John/3 John handled via ordinal + 'John'
    'jude': 'Jude', 'jud': 'Jude',
    'revelation': 'Revelation', 'rev': 'Revelation', 'apocalypse': 'Revelation',
    'apoc': 'Revelation',
  };

  static final Set<String> _ordinalBooks = {
    'Samuel',
    'Kings',
    'Chronicles',
    'Corinthians',
    'Thessalonians',
    'Timothy',
    'Peter',
    'John',
  };

  /// Canonical order and chapter counts for expansion across ranges.
  static const List<String> _bookOrder = [
    'Genesis',
    'Exodus',
    'Leviticus',
    'Numbers',
    'Deuteronomy',
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
    'Job',
    'Psalm',
    'Proverbs',
    'Ecclesiastes',
    'Song of Songs',
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
    'Matthew',
    'Mark',
    'Luke',
    'John',
    'Acts',
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
    'Revelation',
  ];

  static const Map<String, int> _chapters = {
    'Genesis': 50,
    'Exodus': 40,
    'Leviticus': 27,
    'Numbers': 36,
    'Deuteronomy': 34,
    'Joshua': 24,
    'Judges': 21,
    'Ruth': 4,
    '1 Samuel': 31,
    '2 Samuel': 24,
    '1 Kings': 22,
    '2 Kings': 25,
    '1 Chronicles': 29,
    '2 Chronicles': 36,
    'Ezra': 10,
    'Nehemiah': 13,
    'Esther': 10,
    'Job': 42,
    'Psalm': 150,
    'Proverbs': 31,
    'Ecclesiastes': 12,
    'Song of Songs': 8,
    'Isaiah': 66,
    'Jeremiah': 52,
    'Lamentations': 5,
    'Ezekiel': 48,
    'Daniel': 12,
    'Hosea': 14,
    'Joel': 3,
    'Amos': 9,
    'Obadiah': 1,
    'Jonah': 4,
    'Micah': 7,
    'Nahum': 3,
    'Habakkuk': 3,
    'Zephaniah': 3,
    'Haggai': 2,
    'Zechariah': 14,
    'Malachi': 4,
    'Matthew': 28,
    'Mark': 16,
    'Luke': 24,
    'John': 21,
    'Acts': 28,
    'Romans': 16,
    '1 Corinthians': 16,
    '2 Corinthians': 13,
    'Galatians': 6,
    'Ephesians': 6,
    'Philippians': 4,
    'Colossians': 4,
    '1 Thessalonians': 5,
    '2 Thessalonians': 3,
    '1 Timothy': 6,
    '2 Timothy': 4,
    'Titus': 3,
    'Philemon': 1,
    'Hebrews': 13,
    'James': 5,
    '1 Peter': 5,
    '2 Peter': 3,
    '1 John': 5,
    '2 John': 1,
    '3 John': 1,
    'Jude': 1,
    'Revelation': 22,
  };

  static final List<String> _allBooks = List.unmodifiable(_bookOrder);

  /// Returns the canonical list of books in Genesis-to-Revelation order.
  static List<String> get allBooks => _allBooks;

  /// Looks up the number of chapters in [book]. Returns `null` when the book
  /// cannot be resolved to a known entry.
  static int? chapterCount(String book) {
    final ref = _parseEndpoint(book.trim());
    if (ref == null) {
      return null;
    }
    return _chapters[ref.book];
  }

  /// Normalizes a single reference (e.g. "jn 3:16" -> "John 3"). Returns the
  /// trimmed input if parsing fails.
  static String normalizeOne(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return raw;

    // Match optional ordinal, a book name, then a chapter number; ignore verses.
    final re = RegExp(
        r'^\s*(?:(\d|[Ii]{1,3})\s*)?([A-Za-z][A-Za-z .]*?)\s*(\d+)(?::.*)?\s*$');
    final m = re.firstMatch(raw);
    if (m == null) {
      return raw; // Could not parse; leave as-is.
    }

    final ordStr = m.group(1);
    final bookRaw = m.group(2) ?? '';
    final chapStr = m.group(3) ?? '';
    if (chapStr.isEmpty) return raw;
    final chapter = int.tryParse(chapStr) ?? 0;
    if (chapter <= 0) return raw;

    final ordinal = _parseOrdinal(ordStr);
    final bookKey = _canonKey(bookRaw);
    var base = _bookMap[bookKey] ?? _titleCase(bookRaw.trim());

    // Psalm singularize
    if (base == 'Psalms') base = 'Psalm';

    // Apply ordinal if applicable
    String display;
    if (ordinal != null && _ordinalBooks.contains(base)) {
      final ordinalValue = ordinal;
      display = '$ordinalValue $base';
    } else {
      display = base;
    }
    return '$display $chapter';
  }

  /// Normalizes a list of references, removing empties.
  static List<String> normalizeList(Iterable<String> inputs) {
    final out = <String>[];
    for (final s in inputs) {
      final norm = normalizeOne(s);
      if (norm.trim().isNotEmpty) out.add(norm);
    }
    return out;
  }

  /// Returns the next sequential chapter after [reference], or `null` if the
  /// input cannot be parsed or already points to the final chapter in the
  /// canon.
  static String? nextChapter(String reference) {
    final normalized = normalizeOne(reference).trim();
    if (normalized.isEmpty) {
      return null;
    }

    final match = RegExp(r'^(.*\S)\s+(\d+)$').firstMatch(normalized);
    if (match == null) {
      return null;
    }

    final book = match.group(1)!;
    final chapter = int.tryParse(match.group(2)!);
    if (chapter == null) {
      return null;
    }

    final totalChapters = _chapters[book];
    if (totalChapters == null) {
      return null;
    }

    if (chapter < totalChapters) {
      return '$book ${chapter + 1}';
    }

    final index = _bookOrder.indexOf(book);
    if (index == -1 || index + 1 >= _bookOrder.length) {
      return null;
    }

    final nextBook = _bookOrder[index + 1];
    return '$nextBook 1';
  }

  /// Parses a free-form input (commas/semicolons allowed, ranges with '-', '–', '—', 'to')
  /// and returns an expanded list of canonical chapter references.
  static List<String> parseChaptersList(String input) {
    final parts = input
        .split(RegExp(r'[;,]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final out = <String>[];
    for (final part in parts) {
      if (RegExp(r'[-–—]|\bto\b', caseSensitive: false).hasMatch(part)) {
        final rangeSplit =
            part.split(RegExp(r'[-–—]|\bto\b', caseSensitive: false));
        if (rangeSplit.length >= 2) {
          final start = _parseEndpoint(rangeSplit.first.trim());
          var end = _parseEndpoint(rangeSplit.last.trim());
          // Shorthand like "deut 28-31": inherit book from start.
          if (start != null && end == null) {
            final tail = rangeSplit.last.trim();
            if (RegExp(r'^\d+$').hasMatch(tail)) {
              end = _parseEndpoint('${start.book} $tail');
            }
          }
          if (start != null && end != null) {
            out.addAll(_expandRange(start, end));
            continue;
          }
        }
      }
      final single = _parseEndpoint(part);
      if (single != null) {
        out.add('${single.book} ${single.chapter}');
      } else {
        final fallback = normalizeOne(part);
        if (fallback.trim().isNotEmpty) out.add(fallback);
      }
    }
    return out;
  }

  static String? _resolveBookName(String key) {
    var base = _bookMap[key];
    if (base != null) return base;
    final keyStart = _bookMap.keys.firstWhere(
      (k) => k.startsWith(key),
      orElse: () => '',
    );
    if (keyStart.isNotEmpty) return _bookMap[keyStart];
    String? best;
    var bestDist = 3;
    for (final entry in _bookMap.entries) {
      final d = _lev(key, entry.key);
      if (d < bestDist) {
        bestDist = d;
        best = entry.value;
      }
    }
    return best;
  }

  static int _lev(String a, String b) {
    final m = a.length, n = b.length;
    if (m == 0) return n;
    if (n == 0) return m;
    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
    for (var i = 0; i <= m; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= n; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final del = dp[i - 1][j] + 1;
        final ins = dp[i][j - 1] + 1;
        final sub = dp[i - 1][j - 1] + cost;
        dp[i][j] =
            del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
    }
    return dp[m][n];
  }

  static _Ref? _parseEndpoint(String s) {
    final re = RegExp(
        r'^\s*(?:(\d|[Ii]{1,3})\s*)?([A-Za-z][A-Za-z .]*?)(?:\s+(\d+))?\s*$');
    final m = re.firstMatch(s);
    if (m == null) return null;
    final ordStr = m.group(1);
    final rawBook = (m.group(2) ?? '').trim();
    final chapStr = (m.group(3) ?? '').trim();
    final ordinal = _parseOrdinal(ordStr);
    final bookKey = _canonKey(rawBook);
    var base = _resolveBookName(bookKey) ?? _titleCase(rawBook);
    if (base == 'Psalms') base = 'Psalm';
    String displayBook;
    if (ordinal != null && _ordinalBooks.contains(base)) {
      final ordinalValue = ordinal;
      displayBook = '$ordinalValue $base';
    } else {
      displayBook = base;
    }
    final chapters = _chapters[displayBook];
    if (chapters == null) return null;
    int chapter;
    if (chapStr.isEmpty) {
      chapter = 1;
    } else {
      chapter = int.tryParse(chapStr) ?? 1;
    }
    if (chapter < 1) chapter = 1;
    if (chapter > chapters) chapter = chapters;
    final idx = _bookOrder.indexOf(displayBook);
    if (idx == -1) return null;
    return _Ref(displayBook, idx, chapter);
  }

  static List<String> _expandRange(_Ref a, _Ref b) {
    _Ref start = a, end = b;
    if (a.index > b.index || (a.index == b.index && a.chapter > b.chapter)) {
      start = b;
      end = a;
    }
    final result = <String>[];
    for (var i = start.index; i <= end.index; i++) {
      final book = _bookOrder[i];
      final maxCh = _chapters[book] ?? 1;
      final from = i == start.index ? start.chapter : 1;
      final to = i == end.index ? end.chapter : maxCh;
      for (var c = from; c <= to; c++) {
        result.add('$book $c');
      }
    }
    return result;
  }

  static int? _parseOrdinal(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    final asInt = int.tryParse(t);
    if (asInt != null) return asInt;
    switch (t.toUpperCase()) {
      case 'I':
        return 1;
      case 'II':
        return 2;
      case 'III':
        return 3;
      default:
        return null;
    }
  }

  static String _canonKey(String book) {
    var s = book.toLowerCase();
    s = s.replaceAll(RegExp(r'[^a-z0-9]'), '');
    s = s.replaceAll('the', '');
    s = s.replaceAll('of', '');
    return s;
  }

  static String _titleCase(String s) {
    return s
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }
}

class _Ref {
  final String book;
  final int index;
  final int chapter;
  const _Ref(this.book, this.index, this.chapter);
}
