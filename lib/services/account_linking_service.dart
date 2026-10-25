import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/reading_plan_progress.dart';
import 'error_logger.dart';
import 'reading_status_service.dart';

/// Preview and comparison data computed during an account merge dry-run.
class MergeDryRunData {
  /// Dates the guest user marked as read.
  final Set<DateTime> guestDates;

  /// Dates the cloud account marked as read.
  final Set<DateTime> cloudDates;

  /// The union of guest and cloud read dates.
  final Set<DateTime> mergedDates;

  /// Derived reading status for the guest reader alone.
  final ReadingStatus guestStatus;

  /// Derived reading status for the cloud account alone.
  final ReadingStatus cloudStatus;

  /// Derived reading status after merging guest and cloud dates.
  final ReadingStatus mergedStatus;

  /// Reading plans tracked by the guest reader.
  final List<UserPlanProgress> guestPlans;

  /// Reading plans tracked by the cloud account.
  final List<UserPlanProgress> cloudPlans;

  /// Merged and deduplicated reading plans.
  final List<UserPlanProgress> mergedPlans;

  /// UID of the target cloud account, if available.
  final String? targetUid;

  const MergeDryRunData({
    required this.guestDates,
    required this.cloudDates,
    required this.mergedDates,
    required this.guestStatus,
    required this.cloudStatus,
    required this.mergedStatus,
    required this.guestPlans,
    required this.cloudPlans,
    required this.mergedPlans,
    this.targetUid,
  });

  /// Total days read by the guest reader.
  int get guestDays => guestDates.length;

  /// Total days read by the cloud account.
  int get cloudDays => cloudDates.length;

  /// Total days read in the merged dataset.
  int get mergedTotalDays => mergedDates.length;

  /// Recomputed streak of the merged dataset.
  int get mergedStreak => mergedStatus.streak;

  /// Streak of the guest reader.
  int get guestStreak => guestStatus.streak;

  /// Streak of the cloud account.
  int get cloudStreak => cloudStatus.streak;
}

/// Thrown when linking an authentication credential collides with an existing
/// Firebase account (`credential-already-in-use`).
class AccountCollisionException implements Exception {
  /// The credential that collided with an existing account.
  final AuthCredential targetCredential;

  /// Computed dry run comparison between guest and cloud accounts.
  final MergeDryRunData dryRunData;

  /// UID of the collided cloud account.
  final String targetUid;

  /// Human-readable explanation.
  final String message;

  AccountCollisionException({
    required this.targetCredential,
    required this.dryRunData,
    required this.targetUid,
    this.message = 'Credential already associated with another account.',
  });

  @override
  String toString() =>
      'AccountCollisionException: $message (targetUid: $targetUid)';
}

/// Service that manages linking guest readers to persistent credentials,
/// computing dry-run preview statistics, and committing batch merges.
class AccountLinkingService {
  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;
  final DateTime Function() nowProvider;

  FirebaseAuth get auth => _auth ?? FirebaseAuth.instance;
  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;

  AccountLinkingService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    DateTime Function()? nowProvider,
  })  : _auth = auth,
        _firestore = firestore,
        nowProvider = nowProvider ?? DateTime.now;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _formatDateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Fetches all read dates for a user from their `reading` collection.
  Future<Set<DateTime>> fetchReadingDates(String uid) async {
    try {
      final query = await firestore
          .collection('users')
          .doc(uid)
          .collection('reading')
          .get();
      final dates = <DateTime>{};
      for (final doc in query.docs) {
        if (doc.data()['read'] == true) {
          final parsed = DateTime.tryParse(doc.id);
          if (parsed != null) {
            dates.add(_dateOnly(parsed));
          }
        }
      }
      return dates;
    } catch (e, st) {
      ErrorLogger.log(e, st);
      return {};
    }
  }

  /// Fetches all non-deleted plan progress records for [uid].
  Future<List<UserPlanProgress>> fetchPlanProgress(String uid) async {
    try {
      final query = await firestore
          .collection('users')
          .doc(uid)
          .collection('plan_progress')
          .get();
      final plans = <UserPlanProgress>[];
      for (final doc in query.docs) {
        try {
          final plan = UserPlanProgress.fromFirestore(doc);
          if (plan.deletedAt == null) {
            plans.add(plan);
          }
        } catch (e, st) {
          ErrorLogger.log(e, st);
        }
      }
      return plans;
    } catch (e, st) {
      ErrorLogger.log(e, st);
      return [];
    }
  }

  /// Computes a dry-run merge between guest and cloud reading history.
  MergeDryRunData computeMerge({
    required Set<DateTime> guestDates,
    required Set<DateTime> cloudDates,
    required List<UserPlanProgress> guestPlans,
    required List<UserPlanProgress> cloudPlans,
    required DateTime today,
    String? targetUid,
  }) {
    final normGuestDates = guestDates.map(_dateOnly).toSet();
    final normCloudDates = cloudDates.map(_dateOnly).toSet();
    final mergedDates = normGuestDates.union(normCloudDates);
    final normToday = _dateOnly(today);

    final guestStatus = ReadingStatusService.deriveStatusFromDates(
      readDates: normGuestDates,
      today: normToday,
    );
    final cloudStatus = ReadingStatusService.deriveStatusFromDates(
      readDates: normCloudDates,
      today: normToday,
    );
    final mergedStatus = ReadingStatusService.deriveStatusFromDates(
      readDates: mergedDates,
      today: normToday,
      longestStreak:
          math.max(guestStatus.longestStreak, cloudStatus.longestStreak),
    );

    // Merge and deduplicate plans by planId
    final planMap = <String, UserPlanProgress>{};

    for (final p in guestPlans) {
      planMap[p.planId] = p;
    }

    for (final cloudPlan in cloudPlans) {
      final existingGuest = planMap[cloudPlan.planId];
      if (existingGuest == null) {
        planMap[cloudPlan.planId] = cloudPlan;
      } else {
        final mergedCompletedDays = (existingGuest.completedDays.toSet()
              ..addAll(cloudPlan.completedDays))
            .toList()
          ..sort();

        final earliestStart =
            existingGuest.startDate.isBefore(cloudPlan.startDate)
                ? existingGuest.startDate
                : cloudPlan.startDate;

        DateTime? latestLastRead;
        if (existingGuest.lastReadDate != null &&
            cloudPlan.lastReadDate != null) {
          latestLastRead =
              existingGuest.lastReadDate!.isAfter(cloudPlan.lastReadDate!)
                  ? existingGuest.lastReadDate
                  : cloudPlan.lastReadDate;
        } else {
          latestLastRead = existingGuest.lastReadDate ?? cloudPlan.lastReadDate;
        }

        final isArchived = existingGuest.isArchived && cloudPlan.isArchived;

        DateTime? finishedAt;
        if (existingGuest.finishedAt != null && cloudPlan.finishedAt != null) {
          finishedAt = existingGuest.finishedAt!.isAfter(cloudPlan.finishedAt!)
              ? existingGuest.finishedAt
              : cloudPlan.finishedAt;
        } else {
          finishedAt = existingGuest.finishedAt ?? cloudPlan.finishedAt;
        }

        planMap[cloudPlan.planId] = UserPlanProgress(
          planId: cloudPlan.planId,
          userId: targetUid ?? cloudPlan.userId,
          startDate: earliestStart,
          completedDays: mergedCompletedDays,
          lastReadDate: latestLastRead,
          isArchived: isArchived,
          finishedAt: finishedAt,
          deletedAt: null,
        );
      }
    }

    final mergedPlans = planMap.values
        .map((p) => targetUid != null ? p.copyWith(userId: targetUid) : p)
        .toList();

    return MergeDryRunData(
      guestDates: normGuestDates,
      cloudDates: normCloudDates,
      mergedDates: mergedDates,
      guestStatus: guestStatus,
      cloudStatus: cloudStatus,
      mergedStatus: mergedStatus,
      guestPlans: guestPlans,
      cloudPlans: cloudPlans,
      mergedPlans: mergedPlans,
      targetUid: targetUid,
    );
  }

  /// Commits merged reading dates and plan progress records to `users/{targetUid}`
  /// using chunked Firestore batch writes (staying under the 500 ops limit).
  Future<void> commitMerge({
    required String targetUid,
    required Set<DateTime> dates,
    required List<UserPlanProgress> plans,
  }) async {
    final userRef = firestore.collection('users').doc(targetUid);
    final readingCol = userRef.collection('reading');
    final plansCol = userRef.collection('plan_progress');

    final ops = <void Function(WriteBatch batch)>[];

    for (final date in dates) {
      final key = _formatDateKey(_dateOnly(date));
      ops.add((batch) {
        batch.set(
          readingCol.doc(key),
          {'read': true},
          SetOptions(merge: true),
        );
      });
    }

    for (final plan in plans) {
      final targetPlan = plan.copyWith(userId: targetUid);
      ops.add((batch) {
        batch.set(
          plansCol.doc(plan.planId),
          targetPlan.toFirestore(),
          SetOptions(merge: true),
        );
      });
    }

    const chunkSize = 400;
    for (var i = 0; i < ops.length; i += chunkSize) {
      final chunk = ops.sublist(
        i,
        (i + chunkSize > ops.length) ? ops.length : i + chunkSize,
      );
      final batch = firestore.batch();
      for (final op in chunk) {
        op(batch);
      }
      await batch.commit();
    }
  }

  /// Attempts to link [credential] to the currently authenticated reader.
  ///
  /// If the credential is in use by another Firebase user, throws
  /// [AccountCollisionException] containing the dry-run merge statistics so
  /// the UI can present the comparison and prompt the user.
  Future<UserCredential?> linkCredential(AuthCredential credential) async {
    final currentUser = auth.currentUser;
    if (currentUser == null) {
      throw StateError('No current user session to link credential.');
    }

    final guestUid = currentUser.uid;
    final guestDates = await fetchReadingDates(guestUid);
    final guestPlans = await fetchPlanProgress(guestUid);

    try {
      final linkResult = await currentUser.linkWithCredential(credential);
      return linkResult;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        final cloudCred = await auth.signInWithCredential(credential);
        final cloudUid = cloudCred.user!.uid;
        final cloudDates = await fetchReadingDates(cloudUid);
        final cloudPlans = await fetchPlanProgress(cloudUid);

        final dryRun = computeMerge(
          guestDates: guestDates,
          cloudDates: cloudDates,
          guestPlans: guestPlans,
          cloudPlans: cloudPlans,
          today: nowProvider(),
          targetUid: cloudUid,
        );

        throw AccountCollisionException(
          targetCredential: credential,
          dryRunData: dryRun,
          targetUid: cloudUid,
        );
      }
      rethrow;
    }
  }
}
