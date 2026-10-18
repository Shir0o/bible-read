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
