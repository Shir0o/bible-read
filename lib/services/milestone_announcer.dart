import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/read_through.dart';
import 'error_logger.dart';

/// Announces a detected read-through in the feed.
///
/// The announcement is a field on that day's own read-log entry rather than a
/// record of its own: finishing your last chapter *is* reading that day, so the
/// entry already exists or is about to, and riding on it means the milestone
/// inherits the likes and comments that entry already supports.
///
/// Only detected read-throughs are ever announced. Hand-entered and migrated
/// records are claims about the past, and the ledger they live in is
/// owner-only, so nothing else can leak here.
class MilestoneAnnouncer {
  MilestoneAnnouncer({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore firestore;

  /// Writes the milestone for [completed] onto today's read-log entry.
  ///
  /// At most one milestone per user per day, which follows from the entry
  /// being unique per user per day — the same grouping that gives the user a
  /// single celebration.
  Future<void> announce({
    required String uid,
    required List<ReadThrough> completed,
    DateTime? now,
  }) async {
    final announceable =
        completed.where((r) => r.source.isAnnounceable).toList();
    if (announceable.isEmpty) return;

    // The testament is what the reader actually finished; a whole Bible that
    // closed alongside it is the bigger news and rides in the same line.
    final testament = announceable.firstWhere(
      (r) => r.scope != ReadThroughScope.wholeBible,
      orElse: () => announceable.first,
    );
    final wholeBible = completed
        .where((r) => r.scope == ReadThroughScope.wholeBible)
        .firstOrNull;

    final date = now ?? DateTime.now();
    final dateKey = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    try {
      final profile = await firestore.collection('users').doc(uid).get();
      final name = (profile.data()?['name'] as String?) ?? '';

      await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc(uid)
          .set({
        'uid': uid,
        if (name.isNotEmpty) 'name': name,
        'dateId': dateKey,
        'timestamp': Timestamp.fromDate(date),
        'milestone': {
          'scope': testament.scope.id,
          'lapNumber': testament.lapNumber,
          if (wholeBible != null) 'wholeBibleLap': wholeBible.lapNumber,
        },
      }, SetOptions(merge: true));
    } catch (e, st) {
      // The read-through is already recorded; a missed announcement is not
      // worth failing the marking over.
      ErrorLogger.log(e, st);
    }
  }
}

/// The milestone shown on a feed card, when the entry carries one.
class FeedMilestone {
  final ReadThroughScope scope;
  final int lapNumber;

  /// Set when this marking also closed a whole Bible.
  final int? wholeBibleLap;

  const FeedMilestone({
    required this.scope,
    required this.lapNumber,
    this.wholeBibleLap,
  });

  static FeedMilestone? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final scope = raw['scope'];
    if (scope is! String) return null;
    return FeedMilestone(
      scope: ReadThroughScope.fromId(scope),
      lapNumber: (raw['lapNumber'] as num?)?.toInt() ?? 1,
      wholeBibleLap: (raw['wholeBibleLap'] as num?)?.toInt(),
    );
  }

  /// "Finished the New Testament".
  String get headline => 'Finished the ${scope.label}';

  /// "3rd time through · and a 2nd whole Bible".
  String get detail {
    final times = '${_ordinal(lapNumber)} time through';
    if (wholeBibleLap == null) return times;
    return '$times · and a ${_ordinal(wholeBibleLap!)} whole Bible';
  }

  static String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    return switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    };
  }
}
