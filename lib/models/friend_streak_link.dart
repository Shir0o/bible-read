import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of a friend streak link.
enum FriendStreakStatus { pending, active, declined }

/// Firestore model representing a paired streak link between friends.
class FriendStreakLink {
  /// UID for the linked partner.
  final String partnerUid;

  /// Optional display name for the linked partner.
  final String? partnerName;

  /// Identifier describing which user initiated the link.
  final String initiatedBy;

  /// Current status of the link.
  final FriendStreakStatus status;

  /// Current streak length.
  final int currentStreak;

  /// Timestamp for the last day covered by the current user.
  final DateTime? lastUserCovered;

  /// Timestamp for the last day covered by the partner.
  final DateTime? lastPartnerCovered;

  /// Timestamp when the link or invite was created.
  final DateTime createdAt;

  /// Timestamp when the link was last updated.
  final DateTime updatedAt;

  /// UID that owns the document.
  final String ownerUid;

  /// Creates a [FriendStreakLink].
  const FriendStreakLink({
    required this.partnerUid,
    required this.partnerName,
    required this.initiatedBy,
    required this.status,
    required this.currentStreak,
    required this.lastUserCovered,
    required this.lastPartnerCovered,
    required this.createdAt,
    required this.updatedAt,
    required this.ownerUid,
  });

  /// Convenience flag describing whether this link/invite was initiated by
  /// someone else.
  bool get isIncoming => initiatedBy != ownerUid;

  /// Returns whether this link is pending.
  bool get isPending => status == FriendStreakStatus.pending;

  /// Returns whether this link is active.
  bool get isActive => status == FriendStreakStatus.active;

  /// Parses a Firestore document into a [FriendStreakLink].
  factory FriendStreakLink.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String ownerUid,
  }) {
    final data = doc.data() ?? const <String, dynamic>{};
    return FriendStreakLink(
      partnerUid: data['partnerUid'] as String? ?? doc.id,
      partnerName: data['partnerName'] as String?,
      initiatedBy: data['initiatedBy'] as String? ?? ownerUid,
      status: _parseStatus(data['status'] as String?),
      currentStreak: (data['currentStreak'] as num?)?.toInt() ?? 0,
      lastUserCovered: _parseDate(data['lastUserCovered']),
      lastPartnerCovered: _parseDate(data['lastPartnerCovered']),
      createdAt: _parseDate(data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: _parseDate(data['updatedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      ownerUid: ownerUid,
    );
  }

  /// Converts the link to a Firestore map.
  Map<String, dynamic> toFirestore() {
    return {
      'partnerUid': partnerUid,
      if (partnerName != null) 'partnerName': partnerName,
      'initiatedBy': initiatedBy,
      'status': status.name,
      'currentStreak': currentStreak,
      'lastUserCovered':
          lastUserCovered == null ? null : Timestamp.fromDate(lastUserCovered!),
      'lastPartnerCovered': lastPartnerCovered == null
          ? null
          : Timestamp.fromDate(lastPartnerCovered!),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    }..removeWhere((key, value) => value == null);
  }

  static FriendStreakStatus _parseStatus(String? raw) {
    return FriendStreakStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => FriendStreakStatus.pending,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }
}
