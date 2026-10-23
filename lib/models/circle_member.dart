/// One person in the reader's Circle (ADR-0012): a co-member of at least one
/// of the reader's Groups, or a Friend. Derived from Group membership and the
/// friend graph at read time and deduplicated by [uid] — a person who is both
/// appears once, with both Group ids in [groupIds] and [isFriend] set.
class CircleMember {
  /// UID of the person.
  final String uid;

  /// Display name, when the member document, friend document or profile
  /// carries one.
  final String? name;

  /// Profile photo URL, if known.
  final String? photoUrl;

  /// Ids of the Groups the reader shares with this person. Empty for a
  /// Friend with no shared Group.
  final Set<String> groupIds;

  /// Whether the reader is Friends with this person.
  final bool isFriend;

  /// When the two readers became Friends, when known.
  final DateTime? friendSince;

  const CircleMember({
    required this.uid,
    required this.groupIds,
    this.name,
    this.photoUrl,
    this.isFriend = false,
    this.friendSince,
  });
}

/// One person who has shown up today in the reader's Circle (or the reader
/// themselves), resolved with display metadata for the Home "Your circle" card.
class CirclePresencePerson {
  /// UID of the reader.
  final String uid;

  /// Display name resolved from Circle member record, feed entry, or profile.
  /// Falls back to `'?'` when unknown so [MemberPresenceStack] renders a placeholder.
  final String name;

  /// Optional profile photo URL.
  final String? photoUrl;

  const CirclePresencePerson({
    required this.uid,
    required this.name,
    this.photoUrl,
  });

  /// First name for the "X showed up" subtitle, falling back to `'Someone'`.
  String get firstName {
    if (name == '?') return 'Someone';
    final first = name.trim().split(' ').first;
    return first.isEmpty ? 'Someone' : first;
  }
}

/// Immutable snapshot of today's Circle presence for the Home "Your circle" card.
class CirclePresenceSnapshot {
  /// People in the Circle (plus the viewer, if they showed up) who read today.
  final List<CirclePresencePerson> readers;

  /// Total size of the Circle including the viewer (`1 + circleMembers.length`),
  /// or `0` before the initial load completes.
  final int totalCount;

  const CirclePresenceSnapshot({
    required this.readers,
    required this.totalCount,
  });

  /// Unloaded initial state (`totalCount == 0`), hiding the section until loaded.
  static const empty = CirclePresenceSnapshot(
    readers: <CirclePresencePerson>[],
    totalCount: 0,
  );

  /// Whether the Circle total has been resolved (`totalCount > 0`).
  bool get isLoaded => totalCount > 0;

  /// Number of people in the Circle (including the viewer) who read today.
  int get readCount => readers.length;
}
