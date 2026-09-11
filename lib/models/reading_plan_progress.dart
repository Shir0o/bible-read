import 'package:cloud_firestore/cloud_firestore.dart';

/// Tracks a user's progress through a specific reading plan.
class UserPlanProgress {
  final String planId;
  final String userId;
  final DateTime startDate;
  final List<int> completedDays; // List of day numbers that are completed
  final DateTime? lastReadDate;
  final bool isArchived;

  /// When the plan was moved to the Recently Deleted hub (#776). Null while
  /// the plan is live; non-null soft-deleted items are excluded from every
  /// active query.
  final DateTime? deletedAt;

  /// When the soft-deleted plan is permanently purged: [deletedAt] + 30 days.
  final DateTime? deleteAfter;

  /// The state the plan was in when soft-deleted — 'active' or 'archived' —
  /// so restoring returns it to exactly where it was.
  final String? preDeleteState;

  UserPlanProgress({
    required this.planId,
    required this.userId,
    required this.startDate,
    required this.completedDays,
    this.lastReadDate,
    this.isArchived = false,
    this.deletedAt,
    this.deleteAfter,
    this.preDeleteState,
  });

  factory UserPlanProgress.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return UserPlanProgress(
      planId: data['planId'] as String,
      userId: data['userId'] as String,
      startDate: (data['startDate'] as Timestamp).toDate(),
      completedDays: List<int>.from(data['completedDays'] as List? ?? []),
      lastReadDate: (data['lastReadDate'] as Timestamp?)?.toDate(),
      isArchived: data['isArchived'] as bool? ?? false,
      deletedAt: (data['deletedAt'] as Timestamp?)?.toDate(),
      deleteAfter: (data['deleteAfter'] as Timestamp?)?.toDate(),
      preDeleteState: data['preDeleteState'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'planId': planId,
        'userId': userId,
        'startDate': Timestamp.fromDate(startDate),
        'completedDays': completedDays,
        'lastReadDate':
            lastReadDate != null ? Timestamp.fromDate(lastReadDate!) : null,
        'isArchived': isArchived,
        'deletedAt': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null,
        'deleteAfter':
            deleteAfter != null ? Timestamp.fromDate(deleteAfter!) : null,
        'preDeleteState': preDeleteState,
      };

  UserPlanProgress copyWith({
    String? planId,
    String? userId,
    DateTime? startDate,
    List<int>? completedDays,
    DateTime? lastReadDate,
    bool? isArchived,
    DateTime? deletedAt,
    DateTime? deleteAfter,
    String? preDeleteState,
  }) {
    return UserPlanProgress(
      planId: planId ?? this.planId,
      userId: userId ?? this.userId,
      startDate: startDate ?? this.startDate,
      completedDays: completedDays ?? this.completedDays,
      lastReadDate: lastReadDate ?? this.lastReadDate,
      isArchived: isArchived ?? this.isArchived,
      deletedAt: deletedAt ?? this.deletedAt,
      deleteAfter: deleteAfter ?? this.deleteAfter,
      preDeleteState: preDeleteState ?? this.preDeleteState,
    );
  }
}
