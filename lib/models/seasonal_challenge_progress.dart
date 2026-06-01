import 'package:cloud_firestore/cloud_firestore.dart';

/// Tracks a user's progress toward a seasonal challenge.
class SeasonalChallengeProgress {
  /// Firestore document id.
  final String id;

  /// UID of the user earning progress.
  final String uid;

  /// Identifier of the season the challenge belongs to.
  final String seasonId;

  /// Identifier of the challenge definition.
  final String challengeId;

  /// Daily totals keyed by `yyyy-MM-dd`.
  final Map<String, int> dailyProgress;

  /// Total progress accumulated for the challenge.
  final int totalProgress;

  /// Timestamp when the progress was last updated.
  final DateTime? updatedAt;

  /// Timestamp when the challenge was completed.
  final DateTime? completedAt;

  /// Timestamp when the associated reward was claimed.
  final DateTime? rewardClaimedAt;

  /// Creates a [SeasonalChallengeProgress].
  SeasonalChallengeProgress({
    required this.id,
    required this.uid,
    required this.seasonId,
    required this.challengeId,
    Map<String, int>? dailyProgress,
    this.totalProgress = 0,
    this.updatedAt,
    this.completedAt,
    this.rewardClaimedAt,
  }) : dailyProgress = Map<String, int>.unmodifiable(
          dailyProgress ?? <String, int>{},
        );

  /// Reads progress from Firestore.
  factory SeasonalChallengeProgress.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return SeasonalChallengeProgress(
      id: doc.id,
      uid: data['uid'] as String? ?? '',
      seasonId: data['seasonId'] as String? ?? '',
      challengeId: data['challengeId'] as String? ?? '',
      dailyProgress: _parseDailyProgress(data['dailyProgress']),
      totalProgress: _asInt(data['totalProgress']),
      updatedAt: _parseDate(data['updatedAt']),
      completedAt: _parseDate(data['completedAt']),
      rewardClaimedAt: _parseDate(data['rewardClaimedAt']),
    );
  }

  /// Serializes this progress document for Firestore.
  Map<String, dynamic> toFirestore() {
    final data = <String, dynamic>{
      'uid': uid,
      'seasonId': seasonId,
      'challengeId': challengeId,
      'dailyProgress': Map<String, int>.from(dailyProgress),
      'totalProgress': totalProgress,
    };
    if (updatedAt != null) {
      data['updatedAt'] = Timestamp.fromDate(updatedAt!);
    }
    if (completedAt != null) {
      data['completedAt'] = Timestamp.fromDate(completedAt!);
    }
    if (rewardClaimedAt != null) {
      data['rewardClaimedAt'] = Timestamp.fromDate(rewardClaimedAt!);
    }
    return data;
  }

  /// Returns a new instance with updated values.
  SeasonalChallengeProgress copyWith({
    Map<String, int>? dailyProgress,
    int? totalProgress,
    DateTime? updatedAt,
    DateTime? completedAt,
    DateTime? rewardClaimedAt,
  }) {
    return SeasonalChallengeProgress(
      id: id,
      uid: uid,
      seasonId: seasonId,
      challengeId: challengeId,
      dailyProgress: dailyProgress ?? this.dailyProgress,
      totalProgress: totalProgress ?? this.totalProgress,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
      rewardClaimedAt: rewardClaimedAt ?? this.rewardClaimedAt,
    );
  }

  static Map<String, int> _parseDailyProgress(Object? value) {
    if (value is Map<String, int>) {
      return Map<String, int>.from(value);
    }
    if (value is Map<String, dynamic>) {
      return value.map((key, dynamic v) => MapEntry(key, _asInt(v)));
    }
    return <String, int>{};
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

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}
