import 'package:cloud_firestore/cloud_firestore.dart';

/// Tracks a user's progress through a specific reading plan.
class UserPlanProgress {
  final String planId;
  final String userId;
  final DateTime startDate;
  final List<int> completedDays; // List of day numbers that are completed
  final DateTime? lastReadDate;
  final bool isArchived;

  UserPlanProgress({
    required this.planId,
    required this.userId,
    required this.startDate,
    required this.completedDays,
    this.lastReadDate,
    this.isArchived = false,
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
      };

  UserPlanProgress copyWith({
    String? planId,
    String? userId,
    DateTime? startDate,
    List<int>? completedDays,
    DateTime? lastReadDate,
    bool? isArchived,
  }) {
    return UserPlanProgress(
      planId: planId ?? this.planId,
      userId: userId ?? this.userId,
      startDate: startDate ?? this.startDate,
      completedDays: completedDays ?? this.completedDays,
      lastReadDate: lastReadDate ?? this.lastReadDate,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}
