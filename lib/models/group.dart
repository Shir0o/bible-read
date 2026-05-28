import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a Bible reading group.
class Group {
  /// Document id of the group.
  final String id;

  /// Display name of the group.
  final String name;

  /// UID of the user who owns the group.
  final String ownerUid;

  /// Number of members currently in the group.
  final int memberCount;

  /// Whether the group is public and visible in search results.
  final bool isPublic;

  /// Creates a [Group].
  const Group({
    required this.id,
    required this.name,
    required this.ownerUid,
    this.memberCount = 0,
    this.isPublic = false,
  });

  /// Reads a [Group] from a Firestore document.
  factory Group.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Group(
      id: doc.id,
      name: data['name'] as String? ?? '',
      ownerUid: data['ownerUid'] as String? ?? '',
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 0,
      isPublic: data['isPublic'] as bool? ?? false,
    );
  }

  /// Serializes this group for Firestore.
  Map<String, dynamic> toFirestore() => {
    'name': name,
    'ownerUid': ownerUid,
    'memberCount': memberCount,
    'isPublic': isPublic,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Group &&
        other.id == id &&
        other.name == name &&
        other.ownerUid == ownerUid &&
        other.memberCount == memberCount &&
        other.isPublic == isPublic;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        ownerUid.hashCode ^
        memberCount.hashCode ^
        isPublic.hashCode;
  }
}
