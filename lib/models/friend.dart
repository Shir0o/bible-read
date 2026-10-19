/// One side of a mutual Friend connection (ADR-0012).
///
/// A friendship is stored on both readers, one document per side under
/// `users/{uid}/friendships/{friendUid}`. The document id is the other
/// reader's uid; [since] records when the connection was made.
class Friend {
  /// UID of the other reader.
  final String uid;

  /// Display name, as captured when the friendship was made.
  final String? name;

  /// Profile photo URL, as captured when the friendship was made.
  final String? photoUrl;

  /// When the two readers became Friends.
  final DateTime? since;

  const Friend({
    required this.uid,
    this.name,
    this.photoUrl,
    this.since,
  });
}
