import 'dart:convert';
import 'dart:io';

// Data copied from ReferenceParser for standalone execution
const List<String> bookOrder = [
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
  'Revelation'
];

const Map<String, int> chapters = {
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
  'Revelation': 22
};

void main() {
  final otBooks = bookOrder.sublist(0, 39);
  final ntBooks = bookOrder.sublist(39);

  List<String> getAllChapters(List<String> books) {
    final list = <String>[];
    for (final book in books) {
      final count = chapters[book]!;
      for (var c = 1; c <= count; c++) {
        list.add('$book $c');
      }
    }
    return list;
  }

  final allOt = getAllChapters(otBooks);
  final allNt = getAllChapters(ntBooks);

  final schedule = <Map<String, dynamic>>[];
  var day = 1;
  var otIndex = 0;
  var ntIndex = 0;

  // Loop until both are finished.
  // We'll just continue until both OT and NT are exhausted.
  // One might finish before the other.
  while (otIndex < allOt.length || ntIndex < allNt.length) {
    var dailyReadings = <String>[];

    // Add up to 4 OT chapters
    for (var i = 0; i < 4; i++) {
      if (otIndex < allOt.length) {
        dailyReadings.add(allOt[otIndex]);
        otIndex++;
      }
    }

    // Add 1 NT chapter
    if (ntIndex < allNt.length) {
      dailyReadings.add(allNt[ntIndex]);
      ntIndex++;
    }

    schedule.add({
      'day': day,
      'readings': dailyReadings,
    });
    day++;
  }

  final plan = {
    "id": "bible_in_a_year_4_1",
    "title": "Bible in a Year (4 OT, 1 NT)",
    "description":
        "Read through the entire Bible with 4 Old Testament chapters and 1 New Testament chapter daily.",
    "durationDays": schedule.length,
    "tags": ["Full Bible", "Yearly", "4 OT + 1 NT"],
    "schedule": schedule,
  };

  File('assets/plans/sample_plans.json').writeAsStringSync(jsonEncode([plan]));
  print('Generated plan with ${schedule.length} days.');
}
