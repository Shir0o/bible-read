import 'package:cloud_firestore/cloud_firestore.dart';

/// The extent a [ReadThrough] covers.
enum ReadThroughScope {
  oldTestament,
  newTestament,
  wholeBible;

  /// The value stored in Firestore.
  String get id => switch (this) {
        ReadThroughScope.oldTestament => 'ot',
        ReadThroughScope.newTestament => 'nt',
        ReadThroughScope.wholeBible => 'bible',
      };

  /// Human label used throughout the UI.
  String get label => switch (this) {
        ReadThroughScope.oldTestament => 'Old Testament',
        ReadThroughScope.newTestament => 'New Testament',
        ReadThroughScope.wholeBible => 'Whole Bible',
      };

  static ReadThroughScope fromId(String? id) => switch (id) {
        'ot' => ReadThroughScope.oldTestament,
        'nt' => ReadThroughScope.newTestament,
        _ => ReadThroughScope.wholeBible,
      };
}

/// How precisely the user remembers when a [ReadThrough] finished.
///
/// Backfilled entries are often only remembered to the year. The timestamp is
/// always stored in full; this says how much of it to believe and to render.
enum DatePrecision {
  year,
  month,
  day;

  String get id => name;

  static DatePrecision fromId(String? id) => switch (id) {
        'year' => DatePrecision.year,
        'month' => DatePrecision.month,
        _ => DatePrecision.day,
      };
}

/// Where a [ReadThrough] came from.
enum ReadThroughSource {
  /// Inferred from coverage completing a scope. The only kind announced.
  detected,

  /// Entered by hand for reading finished before or outside the app.
  backfilled,

  /// A whole-Bible record, created when an Old and a New Testament
  /// read-through paired off. Never recorded directly.
  derived,

  /// Granted at launch for coverage a user had already earned.
  migrated;

  String get id => name;

  static ReadThroughSource fromId(String? id) => switch (id) {
        'detected' => ReadThroughSource.detected,
        'backfilled' => ReadThroughSource.backfilled,
        'derived' => ReadThroughSource.derived,
        _ => ReadThroughSource.migrated,
      };

  /// Only detected read-throughs reach the feed. Everything else is a claim
  /// about the past, not an event that just happened.
  bool get isAnnounceable => this == ReadThroughSource.detected;

  /// Detected and derived records are the app's own account of what happened,
  /// so they are never deleted — only their human-supplied fields are edited.
  bool get isDeletable =>
      this == ReadThroughSource.backfilled || this == ReadThroughSource.migrated;
}

/// A record that a user finished reading a [ReadThroughScope] end to end.
class ReadThrough {
  /// Firestore document id.
  final String id;

  /// What was finished.
  final ReadThroughScope scope;

  /// When it finished. Read together with [datePrecision].
  final DateTime completedAt;

  /// How much of [completedAt] the user actually remembers.
  final DatePrecision datePrecision;

  /// Free text saying where this happened. Empty when not given.
  final String location;

  /// Where this record came from.
  final ReadThroughSource source;

  /// Whether the celebration for this record has already been shown.
  final bool celebrated;

  /// 1-based position among this user's read-throughs of the same scope,
  /// oldest first. Assigned by the service, not stored by the client.
  final int lapNumber;

  /// For a [ReadThroughSource.derived] record, the two records that paired to
  /// make it. Empty for every other source.
  final String? pairedOtId;
  final String? pairedNtId;

  const ReadThrough({
    required this.id,
    required this.scope,
    required this.completedAt,
    required this.source,
    this.datePrecision = DatePrecision.day,
    this.location = '',
    this.celebrated = false,
    this.lapNumber = 0,
    this.pairedOtId,
    this.pairedNtId,
  });

  factory ReadThrough.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return ReadThrough(
      id: doc.id,
      scope: ReadThroughScope.fromId(data['scope'] as String?),
      completedAt:
          (data['completedAt'] as Timestamp?)?.toDate() ?? DateTime(1970),
      datePrecision: DatePrecision.fromId(data['datePrecision'] as String?),
      location: (data['location'] as String?) ?? '',
      source: ReadThroughSource.fromId(data['source'] as String?),
      celebrated: data['celebrated'] as bool? ?? false,
      pairedOtId: data['pairedOtId'] as String?,
      pairedNtId: data['pairedNtId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'scope': scope.id,
        'completedAt': Timestamp.fromDate(completedAt),
        'datePrecision': datePrecision.id,
        'location': location,
        'source': source.id,
        'celebrated': celebrated,
        if (pairedOtId != null) 'pairedOtId': pairedOtId,
        if (pairedNtId != null) 'pairedNtId': pairedNtId,
      };

  ReadThrough copyWith({
    String? id,
    ReadThroughScope? scope,
    DateTime? completedAt,
    DatePrecision? datePrecision,
    String? location,
    ReadThroughSource? source,
    bool? celebrated,
    int? lapNumber,
    String? pairedOtId,
    String? pairedNtId,
  }) {
    return ReadThrough(
      id: id ?? this.id,
      scope: scope ?? this.scope,
      completedAt: completedAt ?? this.completedAt,
      datePrecision: datePrecision ?? this.datePrecision,
      location: location ?? this.location,
      source: source ?? this.source,
      celebrated: celebrated ?? this.celebrated,
      lapNumber: lapNumber ?? this.lapNumber,
      pairedOtId: pairedOtId ?? this.pairedOtId,
      pairedNtId: pairedNtId ?? this.pairedNtId,
    );
  }

  /// Renders [completedAt] at the precision the user actually gave.
  String get dateLabel => switch (datePrecision) {
        DatePrecision.year => '${completedAt.year}',
        DatePrecision.month =>
          '${_monthNames[completedAt.month - 1]} ${completedAt.year}',
        DatePrecision.day => '${completedAt.day} '
            '${_monthNames[completedAt.month - 1]} ${completedAt.year}',
      };

  /// The date plus the location, when there is one.
  String get subtitle =>
      location.isEmpty ? dateLabel : '$dateLabel · $location';

  /// "1st time", "2nd time", ... for the badge line in lists.
  String get ordinalLabel => '${_ordinal(lapNumber)} time';

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static String _ordinal(int n) {
    if (n <= 0) return '$n';
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    return switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    };
  }
}

/// How many times a user has finished each scope.
class ReadThroughCounts {
  final int oldTestament;
  final int newTestament;

  const ReadThroughCounts({
    required this.oldTestament,
    required this.newTestament,
  });

  static const empty = ReadThroughCounts(oldTestament: 0, newTestament: 0);

  /// Whole-Bible read-throughs are never counted directly: a user has read the
  /// whole Bible as many times as they have read the lesser of the two
  /// testaments.
  int get wholeBible =>
      oldTestament < newTestament ? oldTestament : newTestament;

  int forScope(ReadThroughScope scope) => switch (scope) {
        ReadThroughScope.oldTestament => oldTestament,
        ReadThroughScope.newTestament => newTestament,
        ReadThroughScope.wholeBible => wholeBible,
      };

  /// The lap the user is currently on for [scope] — one past what they have
  /// finished.
  int currentLap(ReadThroughScope scope) => forScope(scope) + 1;
}
