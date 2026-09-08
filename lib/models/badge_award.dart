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

  /// Every badge, in the order they are displayed.
  ///
  /// Completion landmarks — the first book, then the Testaments — plus the
  /// whole-Bible tiers; consistency tiers counting days shown up; and the
  /// finished-Plan award. The server catalogue in
  /// `functions/badge-awarding.js` mirrors these ids.
  static const List<BadgeDefinition> all = [
    BadgeDefinition(
      id: 'first_book',
      title: 'First Book',
      requirement: 'Finish your first book of the Bible',
    ),
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
    BadgeDefinition(
      id: 'days_7',
      title: '7 days of showing up',
      requirement: 'Show up on 7 days',
    ),
    BadgeDefinition(
      id: 'days_30',
      title: '30 days of showing up',
      requirement: 'Show up on 30 days',
    ),
    BadgeDefinition(
      id: 'days_50',
      title: '50 days of showing up',
      requirement: 'Show up on 50 days',
    ),
    BadgeDefinition(
      id: 'days_100',
      title: '100 days of showing up',
      requirement: 'Show up on 100 days',
    ),
    BadgeDefinition(
      id: 'days_365',
      title: '365 days of showing up',
      requirement: 'Show up on 365 days',
    ),
    BadgeDefinition(
      id: 'plan_finished',
      title: 'Finished a Plan',
      requirement: 'Complete every reading in a Plan',
    ),
  ];

  /// The badge with [id], or null when the id is not in the catalogue.
  static BadgeDefinition? byId(String id) {
    for (final badge in all) {
      if (badge.id == id) return badge;
    }
    return null;
  }

  /// How far along the reader is, for the "still to come" line. Returns
  /// null for badges whose progress is not a read-through count.
  int? remainingFor(ReadThroughCounts counts) => switch (id) {
        'first_ot' => 1 - counts.oldTestament,
        'first_nt' => 1 - counts.newTestament,
        'first_bible' => 1 - counts.wholeBible,
        'bible_5' => 5 - counts.wholeBible,
        'bible_10' => 10 - counts.wholeBible,
        _ => null,
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

/// A member's latest badge as mirrored for their co-members.
///
/// The server copies the biggest badge just awarded into
/// `groups/{g}/badges/{uid}` (ADR-0004) — the only achievement path a
/// co-member can read. [dateUnlocked] is when that mirror was written.
class BadgeMirror {
  /// Member uid the mirror points at.
  final String uid;

  /// Server catalogue id of the mirrored badge.
  final String badgeId;

  final DateTime? dateUnlocked;

  const BadgeMirror({
    required this.uid,
    required this.badgeId,
    this.dateUnlocked,
  });

  factory BadgeMirror.fromFirestore(
    String uid,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return BadgeMirror(
      uid: uid,
      badgeId: (data['badgeId'] as String?) ?? '',
      dateUnlocked: (data['dateUnlocked'] as Timestamp?)?.toDate(),
    );
  }

  /// Display title resolved against the client badge catalogue; falls back
  /// to the server id for an unknown badge.
  String get title => BadgeDefinition.byId(badgeId)?.title ?? badgeId;
}
