import 'package:cloud_firestore/cloud_firestore.dart';

/// Tracks progress for the manual reading plan generator.
class ManualPlanProgress {
  /// Reference for the next chapter to schedule.
  final String? nextChapterReference;

  /// Default number of chapters to schedule each day.
  final int? defaultChaptersPerDay;

  /// Date the manual plan was last materialized.
  final DateTime? lastMaterializedDate;

  /// Creates a [ManualPlanProgress].
  const ManualPlanProgress({
    this.nextChapterReference,
    this.defaultChaptersPerDay,
    this.lastMaterializedDate,
  });

  /// Empty progress instance with no metadata.
  const ManualPlanProgress.empty()
      : nextChapterReference = null,
        defaultChaptersPerDay = null,
        lastMaterializedDate = null;

  /// Reads a [ManualPlanProgress] from a Firestore document snapshot.
  factory ManualPlanProgress.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return ManualPlanProgress.fromMap(doc.data());
  }

  /// Reads a [ManualPlanProgress] from a raw map.
  factory ManualPlanProgress.fromMap(Map<String, dynamic>? source) {
    final data = source ?? const <String, dynamic>{};
    final manualData = _firstMap(data, const [
      'manualPlanProgress',
      'manualPlan',
      'manual',
    ]);

    String? nextChapterReference = _firstString(
      manualData,
      data,
      const [
        'nextChapterReference',
        'nextChapterRef',
        'nextChapter',
        'cursorRef',
      ],
    );
    if (nextChapterReference != null && nextChapterReference.isEmpty) {
      nextChapterReference = null;
    }

    final defaultChaptersPerDay = _firstInt(
      manualData,
      data,
      const [
        'defaultChaptersPerDay',
        'chaptersPerDay',
        'defaultChapterCount',
      ],
    );

    final lastMaterializedDate = _firstDate(
      manualData,
      data,
      const [
        'lastMaterializedDate',
        'lastMaterializedAt',
        'lastMaterialized',
        'lastGeneratedAt',
        'lastGenerated',
      ],
    );

    return ManualPlanProgress(
      nextChapterReference: nextChapterReference,
      defaultChaptersPerDay: defaultChaptersPerDay,
      lastMaterializedDate: lastMaterializedDate,
    );
  }

  /// Serialises this instance to a Firestore map.
  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{};
    if (nextChapterReference != null) {
      map['nextChapterReference'] = nextChapterReference;
    }
    if (defaultChaptersPerDay != null) {
      map['defaultChaptersPerDay'] = defaultChaptersPerDay;
    }
    if (lastMaterializedDate != null) {
      map['lastMaterializedDate'] = Timestamp.fromDate(
        DateTime.utc(
          lastMaterializedDate!.year,
          lastMaterializedDate!.month,
          lastMaterializedDate!.day,
        ),
      );
    }
    return map;
  }

  /// Creates a copy with overrides.
  ///
  /// When a `clear*` flag is provided the corresponding field will be set to
  /// `null` even if an override value is not supplied.
  ManualPlanProgress copyWith({
    String? nextChapterReference,
    bool clearNextChapterReference = false,
    int? defaultChaptersPerDay,
    bool clearDefaultChaptersPerDay = false,
    DateTime? lastMaterializedDate,
    bool clearLastMaterializedDate = false,
  }) {
    return ManualPlanProgress(
      nextChapterReference: clearNextChapterReference
          ? null
          : nextChapterReference ?? this.nextChapterReference,
      defaultChaptersPerDay: clearDefaultChaptersPerDay
          ? null
          : defaultChaptersPerDay ?? this.defaultChaptersPerDay,
      lastMaterializedDate: clearLastMaterializedDate
          ? null
          : lastMaterializedDate ?? this.lastMaterializedDate,
    );
  }

  static Map<String, dynamic>? _firstMap(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value is Map<String, dynamic>) {
        return value;
      }
    }
    return null;
  }

  static String? _firstString(
    Map<String, dynamic>? manualData,
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = manualData?[key] ?? data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  static int? _firstInt(
    Map<String, dynamic>? manualData,
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = manualData?[key] ?? data[key];
      if (value is num) {
        final intValue = value.toInt();
        if (intValue > 0) {
          return intValue;
        }
      }
    }
    return null;
  }

  static DateTime? _firstDate(
    Map<String, dynamic>? manualData,
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = manualData?[key] ?? data[key];
      final parsed = _parseDate(value);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) {
      final date = value.toDate().toUtc();
      return DateTime.utc(date.year, date.month, date.day);
    }
    if (value is DateTime) {
      final date = value.toUtc();
      return DateTime.utc(date.year, date.month, date.day);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      final parsed = DateTime.tryParse(trimmed);
      if (parsed != null) {
        return DateTime.utc(parsed.year, parsed.month, parsed.day);
      }
    }
    if (value is num) {
      final raw = value.toInt();
      if (raw > 0) {
        final isSeconds = raw < 1000000000000;
        final millis = isSeconds ? raw * 1000 : raw;
        final date = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
        return DateTime.utc(date.year, date.month, date.day);
      }
    }
    return null;
  }
}
