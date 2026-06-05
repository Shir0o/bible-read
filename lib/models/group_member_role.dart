import 'package:cloud_firestore/cloud_firestore.dart';

/// A member of a reading group together with their role and profile basics.
///
/// Sourced from the `groups/{groupId}/members/{uid}` documents. Read status is
/// tracked separately (see `GroupMemberProgressData`) and merged in the UI.
class GroupMemberRole {
  /// UID of the member.
  final String uid;

  /// Display name of the member, if known.
  final String? name;

  /// Profile photo URL, if known.
  final String? photoUrl;

  /// Role within the group: `owner`, `admin`, or `member`.
  final String role;

  /// Creates a [GroupMemberRole].
  const GroupMemberRole({
    required this.uid,
    required this.role,
    this.name,
    this.photoUrl,
  });

  /// Reads a [GroupMemberRole] from a member document.
  factory GroupMemberRole.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final name = (data['name'] as String?)?.trim();
    final photoUrl = (data['photoUrl'] as String?)?.trim();
    return GroupMemberRole(
      uid: (data['uid'] as String?) ?? doc.id,
      role: (data['role'] as String?) ?? 'member',
      name: (name != null && name.isNotEmpty) ? name : null,
      photoUrl: (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : null,
    );
  }

  /// Sort rank for roles: owner first, then admins, then members.
  int get roleRank => switch (role) {
        'owner' => 0,
        'admin' => 1,
        _ => 2,
      };
}
