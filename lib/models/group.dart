import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a Bible reading group.
class Group {
  /// Document id of the group.
  final String id;

  /// Display name of the group.
  final String name;

  /// UID of the user who owns the group.
  final String ownerUid;

  /// Whether the group is publicly visible.
  final bool isPublic;

  /// Creates a [Group].
  const Group({
    required this.id,
    required this.name,
    required this.ownerUid,
    this.isPublic = true,
  });

  /// Reads a [Group] from a Firestore document.
  factory Group.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Group(
      id: doc.id,
      name: data['name'] as String? ?? '',
      ownerUid: data['ownerUid'] as String? ?? '',
      isPublic: data['isPublic'] as bool? ?? true,
    );
  }

  /// Serializes this group for Firestore.
  Map<String, dynamic> toFirestore() => {
        'name': name,
        'ownerUid': ownerUid,
        'isPublic': isPublic,
      };
}
