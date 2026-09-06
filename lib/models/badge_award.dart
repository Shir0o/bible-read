import 'package:cloud_firestore/cloud_firestore.dart';

import 'read_through.dart';

/// A durable award for reaching a read-through landmark.
///
/// Badges are earned once and never lost, unlike a lap, which resets.
class BadgeDefinition {
  /// Firestore document id under `users/{uid}/achievements`.
  final String id;

  final String title;

  /// One line saying what it took, shown under the title.
  final String requirement;

  const BadgeDefinition({
    required this.id,
    required this.title,
    required this.requirement,
  });

  /// Every read-through badge, in the order they are displayed.
  ///
  /// Three landmarks that happen once, then two tiers far enough out to still
  /// be ahead of a reader who has been at this for years.
  static const List<BadgeDefinition> all = [
    BadgeDefinition(
      id: 'first_bible',
      title: 'First whole Bible',
      requirement: 'Finish the Old and New Testaments',
    ),
    BadgeDefinition(
      id: 'first_ot',
      title: 'First Old Testament',
      requirement: 'Finish all 39 books',
    ),
    BadgeDefinition(
      id: 'first_nt',
      title: 'First New Testament',
      requirement: 'Finish all 27 books',
    ),
    BadgeDefinition(
      id: 'bible_5',
      title: 'Five whole Bibles',
      requirement: 'Read the whole Bible 5 times',
    ),
    BadgeDefinition(
      id: 'bible_10',
      title: 'Ten whole Bibles',
      requirement: 'Read the whole Bible 10 times',
    ),
  ];

  /// Whether [counts] earns this badge.
  bool isEarnedBy(ReadThroughCounts counts) => switch (id) {
        'first_ot' => counts.oldTestament >= 1,
        'first_nt' => counts.newTestament >= 1,
        'first_bible' => counts.wholeBible >= 1,
        'bible_5' => counts.wholeBible >= 5,
        'bible_10' => counts.wholeBible >= 10,
        _ => false,
      };

  /// How far along the reader is, for the "still to come" line.
  int remainingFor(ReadThroughCounts counts) => switch (id) {
        'first_ot' => 1 - counts.oldTestament,
        'first_nt' => 1 - counts.newTestament,
        'first_bible' => 1 - counts.wholeBible,
        'bible_5' => 5 - counts.wholeBible,
        'bible_10' => 10 - counts.wholeBible,
        _ => 0,
      };
}

/// A badge the user has actually been awarded.
class BadgeAward {
  final String id;
  final String title;
  final DateTime? unlockedAt;

  const BadgeAward({required this.id, required this.title, this.unlockedAt});

  factory BadgeAward.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return BadgeAward(
      id: doc.id,
      title: (data['title'] as String?) ?? doc.id,
      unlockedAt: (data['dateUnlocked'] as Timestamp?)?.toDate(),
    );
  }
}
