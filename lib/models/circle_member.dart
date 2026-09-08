/// One person in the reader's Circle (ADR-0003): a co-member of at least one
/// of the reader's Groups. Derived from Group membership at read time and
/// deduplicated by [uid] — a person shared between two Groups appears once,
/// with both Group ids in [groupIds].
class CircleMember {
  /// UID of the person.
  final String uid;

  /// Display name, when the member document or profile carries one.
  final String? name;

  /// Profile photo URL, if known.
  final String? photoUrl;

  /// Ids of the Groups the reader shares with this person.
  final Set<String> groupIds;

  const CircleMember({
    required this.uid,
    required this.groupIds,
    this.name,
    this.photoUrl,
  });
}