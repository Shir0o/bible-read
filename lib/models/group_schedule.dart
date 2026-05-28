import 'package:cloud_firestore/cloud_firestore.dart';

/// Daily reading assignment for a group.
class GroupSchedule {
  /// Date the chapters are assigned.
  final DateTime date;

  /// Bible chapter references scheduled for [date].
  final List<String> chapters;

  /// Creates a [GroupSchedule].
  const GroupSchedule({required this.date, required this.chapters});

  /// Reads a [GroupSchedule] from a Firestore document.
  factory GroupSchedule.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final parsedDate =
        DateTime.tryParse(doc.id) ??
        (data['date'] is Timestamp
            ? (data['date'] as Timestamp).toDate().toLocal()
            : DateTime.now());
    return GroupSchedule(
      date: parsedDate,
      chapters:
          (data['chapters'] as List?)?.whereType<String>().toList() ??
          <String>[],
    );
  }

  /// Serializes this schedule for Firestore.
  Map<String, dynamic> toFirestore() => {
    'date': Timestamp.fromDate(DateTime.utc(date.year, date.month, date.day)),
    'chapters': chapters,
  };
}
