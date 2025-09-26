import 'package:flutter/foundation.dart';

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
    final needsOrdinal = ordinal != null && _ordinalBooks.contains(base);
    final display = needsOrdinal ? '${ordinal!} $base' : base;
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
