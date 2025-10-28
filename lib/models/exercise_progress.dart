import 'package:cloud_firestore/cloud_firestore.dart';

/// Aggregated per-day totals for all exercise challenges owned by a user.
class ExerciseProgress {
  /// Firestore document identifier (usually `yyyy-MM-dd`).
  final String id;

  /// UID of the user that recorded the progress.
  final String uid;

  /// Calendar date the progress applies to (normalized to midnight).
  final DateTime date;

  /// Totals recorded for each challenge keyed by challenge id.
  final Map<String, double> totals;

  /// Timestamp when the document was last updated.
  final DateTime? updatedAt;

  /// Creates an [ExerciseProgress].
  ExerciseProgress({
    required this.id,
    required this.uid,
    required this.date,
    Map<String, double>? totals,
    this.updatedAt,
  }) : totals = Map.unmodifiable(totals ?? <String, double>{});

  /// Reads progress from Firestore.
  factory ExerciseProgress.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return ExerciseProgress(
      id: doc.id,
      uid: data['uid'] as String? ?? '',
      date: _parseDate(data['date']) ?? _inferDateFromId(doc.id),
      totals: _parseTotals(data['totals']),
      updatedAt: _parseDate(data['updatedAt']),
    );
  }

  /// Serializes this progress for Firestore writes.
  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'date': Timestamp.fromDate(date),
      'totals': totals,
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  /// Returns the total recorded for [challengeId].
  double totalForChallenge(String challengeId) {
    return totals[challengeId] ?? 0;
  }

  ExerciseProgress copyWith({
    DateTime? date,
    Map<String, double>? totals,
    DateTime? updatedAt,
  }) {
    return ExerciseProgress(
      id: id,
      uid: uid,
      date: date ?? this.date,
      totals: totals ?? this.totals,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.round());
    }
    return null;
  }

  static DateTime _inferDateFromId(String id) {
    final parsed = DateTime.tryParse(id);
    if (parsed != null) {
      return parsed;
    }
    final parts = id.split('-');
    if (parts.length == 3) {
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);
      if (year != null && month != null && day != null) {
        return DateTime(year, month, day);
      }
    }
    return DateTime.now();
  }

  static Map<String, double> _parseTotals(Object? value) {
    if (value is Map<String, double>) {
      return Map<String, double>.from(value);
    }
    if (value is Map<String, dynamic>) {
      return value.map((key, dynamic v) => MapEntry(key, _asDouble(v)));
    }
    return <String, double>{};
  }

  static double _asDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }
}
