import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a seasonal event with a fixed time window.
class Season {
  /// Firestore identifier for the season.
  final String id;

  /// Display title shown to users.
  final String title;

  /// Long-form description of the season.
  final String description;

  /// Start date for the season.
  final DateTime startDate;

  /// End date for the season.
  final DateTime endDate;

  /// Optional banner image displayed in the UI.
  final String bannerImageUrl;

  /// Creates a [Season].
  const Season({
    required this.id,
    required this.title,
    required this.description,
    required this.startDate,
    required this.endDate,
    this.bannerImageUrl = '',
  });

  /// Reads a [Season] from Firestore.
  factory Season.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Season(
      id: doc.id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      startDate: _parseDate(data['startDate']) ?? DateTime.now(),
      endDate: _parseDate(data['endDate']) ?? DateTime.now(),
      bannerImageUrl: data['bannerImageUrl'] as String? ?? '',
    );
  }

  /// Serializes this season for Firestore writes.
  Map<String, dynamic> toFirestore() => {
        'title': title,
        'description': description,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
        'bannerImageUrl': bannerImageUrl,
      };

  /// Returns whether the season is currently active relative to [now].
  bool isActive(DateTime now) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    return !now.isBefore(start) && !now.isAfter(end);
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
}
