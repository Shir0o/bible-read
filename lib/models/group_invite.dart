import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents an invitation to join a reading group.
class GroupInvite {
  /// Unique ID of the invitation.
  final String id;

  /// ID of the group the user is invited to.
  final String groupId;

  /// Display name of the group.
  final String groupName;

  /// UID of the user who sent the invitation.
  final String senderUid;

  /// Display name of the sender.
  final String senderName;

  /// UID of the user receiving the invitation.
  final String recipientUid;

  /// When the invitation was sent.
  final DateTime timestamp;

  /// Creates a [GroupInvite].
  const GroupInvite({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.senderUid,
    required this.senderName,
    required this.recipientUid,
    required this.timestamp,
  });

  /// Reads a [GroupInvite] from a Firestore document.
  factory GroupInvite.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return GroupInvite(
      id: doc.id,
      groupId: data['groupId'] as String? ?? '',
      groupName: data['groupName'] as String? ?? '',
      senderUid: data['senderUid'] as String? ?? '',
      senderName: data['senderName'] as String? ?? '',
      recipientUid: data['recipientUid'] as String? ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Serializes this invite for Firestore.
  Map<String, dynamic> toFirestore() => {
    'groupId': groupId,
    'groupName': groupName,
    'senderUid': senderUid,
    'senderName': senderName,
    'recipientUid': recipientUid,
    'timestamp': FieldValue.serverTimestamp(),
  };
}
