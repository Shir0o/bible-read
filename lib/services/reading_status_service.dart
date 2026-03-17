import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'error_logger.dart';

/// Result of fetching read status data.
class ReadingStatus {
  /// Whether the user has marked today as read.
  final bool readToday;

  /// Flags for each day of the current week (Sunday to Saturday).
  final List<bool> pastWeek;

  /// Flags for each day of the current month.
  final List<bool> pastMonth;

  /// Set of all dates currently loaded as read.
  final Set<DateTime> readDates;

  /// Current streak count.
  final int streak;

  /// Remaining grace credits available for the current summary month.
  final int graceCreditsAvailable;

  /// Identifier of the month associated with [graceCreditsAvailable].
  final String graceCreditsMonth;

  /// Creates a [ReadingStatus].
  const ReadingStatus({
    required this.readToday,
    required this.pastWeek,
    required this.pastMonth,
    required this.readDates,
    required this.streak,
    required this.graceCreditsAvailable,
    required this.graceCreditsMonth,
  });
}

/// Summary statistics returned after updating the summary document.
class SummaryStats {
  /// Consecutive days the user has read up to today.
  final int streak;

  /// Total number of days the user has read.
  final int totalReadDays;

  /// Number of grace credits remaining for the active month.
  final int graceCreditsAvailable;

  /// Number of grace credits consumed for the active month.
  final int graceCreditsUsed;

  /// Identifier of the month the grace credit counters apply to.
  final String graceCreditsMonth;

  /// Date that was just counted toward the streak when the summary ran.
  final DateTime? coveredDate;

  /// Whether [coveredDate] was satisfied by a grace credit instead of a read.
  final bool coveredViaGrace;

  /// Creates [SummaryStats].
  const SummaryStats({
    required this.streak,
    required this.totalReadDays,
    required this.graceCreditsAvailable,
    required this.graceCreditsUsed,
    required this.graceCreditsMonth,
    required this.coveredDate,
    required this.coveredViaGrace,
  });
}

/// Service responsible for reading status and summary calculations.
class ReadingStatusService {
  /// Firestore instance used for database operations.
  final FirebaseFirestore firestore;

  /// Authentication instance for the current user.
  final FirebaseAuth auth;

  /// Provides the current timestamp. Tests can override this to evaluate
  /// calculations against a fixed point in time.
  final DateTime Function() nowProvider;

  /// Creates a [ReadingStatusService] using default Firebase instances.
  ReadingStatusService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    DateTime Function()? dateProvider,
    DateTime Function()? nowProvider,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        nowProvider = nowProvider ?? dateProvider ?? DateTime.now;

  /// Fetches today's read flag and calendar history. Ensures the user
  /// document exists and backfills missing calendar entries.
  Future<ReadingStatus> fetchStatus() async {
    final user = auth.currentUser;
    final today = _dateOnly(nowProvider());
    if (user == null) {
      final defaultMonthKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}';
      return ReadingStatus(
        readToday: false,
        pastWeek: [],
        pastMonth: [],
        readDates: {},
        streak: 0,
        graceCreditsAvailable: 0,
        graceCreditsMonth: defaultMonthKey,
      );
    }

    try {
      final defaultMonthKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}';
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final userDocRef = firestore.collection('users').doc(user.uid);

      // Kick off all reads in parallel.
      final snapshots =
          await Future.wait<DocumentSnapshot<Map<String, dynamic>>>([
        userDocRef.get(),
        userDocRef.collection('reading').doc(dateKey).get(),
        userDocRef.collection('summary').doc('data').get(),
      ], eagerError: true);

      final userDoc = snapshots[0];
      final todayDoc = snapshots[1];
      final summaryDoc = snapshots[2];

      if (!userDoc.exists) {
        await user.reload();
        final refreshedUser = auth.currentUser;

        await userDocRef.set({
          'name': refreshedUser?.displayName ?? '',
          'email': refreshedUser?.email?.toLowerCase() ?? '',
        });

        // Initialize subcollections so later queries succeed.
        final friendsCollection = userDocRef.collection('friends');
        final friendRequestsSentCollection = userDocRef.collection(
          'friendRequestsSent',
        );

        await Future.wait([
          friendsCollection.doc('init').set({
            'status': 'placeholder',
            'timestamp': Timestamp.now(),
          }, SetOptions(merge: true)),
          friendRequestsSentCollection.doc('init').set({
            'status': 'placeholder',
            'timestamp': Timestamp.now(),
          }, SetOptions(merge: true)),
        ]);
      }

      bool readToday = false;
      if (todayDoc.exists && todayDoc.data() != null) {
        final data = todayDoc.data()!;
        readToday = data.containsKey('read') ? data['read'] : false;
      }

      // Load calendar data from summary doc.
      final data = summaryDoc.data() ?? {};
      final streak = (data['streak'] as int?) ?? 0;
      final graceCreditsRaw = data['graceCreditsAvailable'];
      final graceCreditsAvailable = graceCreditsRaw is int
          ? graceCreditsRaw
          : graceCreditsRaw is num
              ? graceCreditsRaw.toInt()
              : 0;
      final graceCreditsMonth =
          (data['graceCreditsMonth'] as String?) ?? defaultMonthKey;
      var weekDates = List<String>.from(data['pastWeekReadDates'] ?? []);
      weekDates = weekDates.where((d) {
        final parsed = DateTime.tryParse(d);
        if (parsed == null) return false;
        final diff = today.difference(parsed).inDays;
        return diff >= 0 && diff < 7;
      }).toList();
      final savedWeek = List<bool>.filled(7, false, growable: true);
      // Compute this week's Sunday (calendar week: Sunday to Saturday)
      final currentWeekday = today.weekday; // 1 = Mon, ..., 7 = Sun
      final sunday = _shiftDate(today, -(currentWeekday % 7));
      for (int i = 0; i < 7; i++) {
        final date = _shiftDate(sunday, i); // Sunday to Saturday
        final key =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        savedWeek[i] = weekDates.contains(key);
      }

      final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
      var monthDates = List<String>.from(data['pastMonthReadDates'] ?? []);
      monthDates = monthDates.where((d) {
        final parsed = DateTime.tryParse(d);
        if (parsed == null) return false;
        return parsed.year == today.year && parsed.month == today.month;
      }).toList();

      final monthStatus = <String, bool>{};
      for (final key in monthDates) {
        monthStatus[key] = true;
      }

      if (weekDates.length < 7) {
        // Backfill the past week by querying reading documents directly.
        final weekStatus = await _getReadStatusForRange(
          user.uid,
          7,
          referenceDate: today,
        );
        savedWeek.clear();
        for (int i = 0; i < 7; i++) {
          final date = _shiftDate(sunday, i);
          final key =
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          savedWeek.add(weekStatus[key] ?? false);
        }
      }
      if (monthDates.length < daysInMonth) {
        // Backfill the past month similarly.
        final backfillStatus = await _getReadStatusForRange(
          user.uid,
          daysInMonth,
          referenceDate: today,
        );
        monthStatus.addAll(backfillStatus);
      }

      final savedMonth = List<bool>.filled(daysInMonth, false, growable: true);
      for (final entry in monthStatus.entries) {
        if (entry.value != true) {
          continue;
        }
        final parsed = DateTime.tryParse(entry.key);
        if (parsed == null) {
          continue;
        }
        if (parsed.year != today.year || parsed.month != today.month) {
          continue;
        }
        final dayIndex = parsed.day - 1;
        if (dayIndex >= 0 && dayIndex < savedMonth.length) {
          savedMonth[dayIndex] = true;
        }
      }

      final readDates = <DateTime>{};
      for (int i = 0; i < savedWeek.length; i++) {
        if (savedWeek[i]) {
          final date = _shiftDate(sunday, i);
          readDates.add(DateTime(date.year, date.month, date.day));
        }
      }
      for (int i = 0; i < savedMonth.length; i++) {
        if (savedMonth[i]) {
          readDates.add(DateTime(today.year, today.month, i + 1));
        }
      }

      return ReadingStatus(
        readToday: readToday,
        pastWeek: savedWeek,
        pastMonth: savedMonth,
        readDates: readDates,
        streak: streak,
        graceCreditsAvailable: graceCreditsAvailable,
        graceCreditsMonth: graceCreditsMonth,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Error fetching status: $e');
      }
      ErrorLogger.log(e, st);
      rethrow;
    }
  }

  /// Cleans and updates the summary document without scanning the entire
  /// reading collection.
  Future<SummaryStats> updateSummary() async {
    final user = auth.currentUser;
    final today = _dateOnly(nowProvider());
    if (user == null) {
      final monthKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}';
      return SummaryStats(
        streak: 0,
        totalReadDays: 0,
        graceCreditsAvailable: 2,
        graceCreditsUsed: 0,
        graceCreditsMonth: monthKey,
        coveredDate: null,
        coveredViaGrace: false,
      );
    }

    try {
      final userDocRef = firestore.collection('users').doc(user.uid);
      final summaryDocRef = userDocRef.collection('summary').doc('data');

      String formatDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      String formatMonth(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}';

      // 1. Fetch current summary baseline.
      final summarySnap = await summaryDocRef.get();
      final summaryExists = summarySnap.exists;
      final summaryData = summarySnap.data() ?? {};
      int oldTotalReadDays = (summaryData['totalReadDays'] as int?) ?? 0;
      int oldLongestStreak = (summaryData['longestStreak'] as int?) ?? 0;

      // 2. Fetch logs. If summary is missing, we must do a full scan once.
      // Otherwise, we use a 90-day sliding window.
      final ninetyDaysAgo = today.subtract(const Duration(days: 90));
      final startId = formatDate(ninetyDaysAgo);
      final endId = formatDate(today);

      QuerySnapshot<Map<String, dynamic>> readingSnapshot;
      if (!summaryExists) {
        readingSnapshot = await userDocRef.collection('reading').get();
      } else {
        readingSnapshot = await userDocRef
            .collection('reading')
            .where(FieldPath.documentId, isGreaterThanOrEqualTo: startId)
            .where(FieldPath.documentId, isLessThanOrEqualTo: endId)
            .get();
      }

      final readDateSet = <String>{};
      for (final readDoc in readingSnapshot.docs) {
        if (readDoc.data()['read'] == true) {
          readDateSet.add(readDoc.id);
        }
      }

      // 3. Backfill from read_logs for missing documents in the recent window.
      // This is important for "feed only" reads.
      final missingDateIds = <String>[];
      const checkRange = 90;
      for (int i = 0; i < checkRange; i++) {
        final d = _shiftDate(today, -i);
        final key = formatDate(d);
        if (!readDateSet.contains(key)) {
          missingDateIds.add(key);
        }
      }

      if (missingDateIds.isNotEmpty) {
        // ⚡ Bolt: Fetch missing logs in parallel (chunked to 30 to avoid overwhelming the network and match whereIn limits).
        const chunkSize = 30;
        for (var i = 0; i < missingDateIds.length; i += chunkSize) {
          final chunk = missingDateIds.sublist(
            i,
            i + chunkSize > missingDateIds.length
                ? missingDateIds.length
                : i + chunkSize,
          );
          final futures = chunk.map((id) async {
            try {
              final entry = await firestore
                  .collection('read_logs')
                  .doc(id)
                  .collection('entries')
                  .doc(user.uid)
                  .get();
              if (entry.exists) {
                return id;
              }
            } catch (e, st) {
              // Best effort; log errors but don't fail summary update.
              if (kDebugMode) debugPrint('Backfill check failed for $id: $e');
              ErrorLogger.log(e, st);
            }
            return null;
          });

          final results = await Future.wait(futures);
          for (final id in results) {
            if (id != null) {
              readDateSet.add(id);
            }
          }
        }
      }

      // 4. Update counters.
      if (!summaryExists) {
        oldTotalReadDays = readDateSet.length;
        // Re-calculate the original-style longest streak (no grace credits)
        // only during the initial full scan to match existing expectations.
        if (readDateSet.isNotEmpty) {
          final sortedAll = readDateSet.map(DateTime.parse).toList()..sort();
          int current = 1;
          oldLongestStreak = 1;
          for (int i = 1; i < sortedAll.length; i++) {
            if (sortedAll[i].difference(sortedAll[i - 1]).inDays == 1) {
              current += 1;
            } else {
              current = 1;
            }
            if (current > oldLongestStreak) {
              oldLongestStreak = current;
            }
          }
        }
      } else {
        final todayKey = formatDate(today);
        if (readDateSet.contains(todayKey)) {
          final pastMonth =
              List<String>.from(summaryData['pastMonthReadDates'] ?? []);
          if (!pastMonth.contains(todayKey)) {
            oldTotalReadDays += 1;
          }
        }
      }

      // Re-build recent status maps for the UI.
      final weekStatus = <String, bool>{};
      for (int i = 0; i < 7; i++) {
        final d = _shiftDate(today, -i);
        final key = formatDate(d);
        weekStatus[key] = readDateSet.contains(key);
      }

      final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
      final monthStatus = <String, bool>{};
      for (int i = 0; i < daysInMonth; i++) {
        final d = DateTime(today.year, today.month, i + 1);
        final key = formatDate(d);
        monthStatus[key] = readDateSet.contains(key);
      }

      final pastWeekReadDates =
          weekStatus.entries.where((e) => e.value).map((e) => e.key).toList();
      final pastMonthReadDates =
          monthStatus.entries.where((e) => e.value).map((e) => e.key).toList();

      final sortedDates = readDateSet.map(DateTime.parse).toList()..sort();

      final currentMonthKey = formatMonth(today);
      final summaryComputation = sortedDates.isNotEmpty
          ? _computeStreakAndCredits(
              today: today,
              sortedDates: sortedDates,
              readDateSet: readDateSet,
              formatDate: formatDate,
              formatMonth: formatMonth,
            )
          : _SummaryComputation(
              streak: 0,
              monthLedgers: {
                currentMonthKey: _MonthlyCreditLedger(
                  monthKey: currentMonthKey,
                  monthStart: DateTime(today.year, today.month, 1),
                ),
              },
              coveredDate: null,
              coveredViaGrace: false,
            );

      final currentMonthCredits =
          summaryComputation.monthLedgers[currentMonthKey] ??
              _MonthlyCreditLedger(
                monthKey: currentMonthKey,
                monthStart: DateTime(today.year, today.month, 1),
              );

      final streak = summaryComputation.streak;
      final longestStreak =
          streak > oldLongestStreak ? streak : oldLongestStreak;

      await summaryDocRef.set({
        'streak': streak,
        'pastWeekReadDates': pastWeekReadDates,
        'pastMonthReadDates': pastMonthReadDates,
        'totalReadDays': oldTotalReadDays,
        'longestStreak': longestStreak,
        'graceCreditsMonth': currentMonthKey,
        'graceCreditsAvailable': currentMonthCredits.available(today),
        'graceCreditsUsed': currentMonthCredits.used,
      }, SetOptions(merge: true));

      return SummaryStats(
        streak: streak,
        totalReadDays: oldTotalReadDays,
        graceCreditsAvailable: currentMonthCredits.available(today),
        graceCreditsUsed: currentMonthCredits.used,
        graceCreditsMonth: currentMonthKey,
        coveredDate: summaryComputation.coveredDate,
        coveredViaGrace: summaryComputation.coveredViaGrace,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to update summary: $e');
      }
      ErrorLogger.log(e, st);
      rethrow;
    }
  }

  Future<Map<String, bool>> _getReadStatusForRange(
    String uid,
    int daysBack, {
    DateTime? referenceDate,
  }) async {
    final userDocRef = firestore.collection('users').doc(uid);
    final readingCollection = userDocRef.collection('reading');

    final base = referenceDate != null
        ? _dateOnly(referenceDate)
        : _dateOnly(nowProvider());
    final now = base;
    String formatDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final startDate = _shiftDate(now, -(daysBack - 1));
    final startId = formatDate(startDate);
    final endId = formatDate(now);

    final querySnapshot = await readingCollection
        .where(
          FieldPath.documentId,
          isGreaterThanOrEqualTo: startId,
          isLessThanOrEqualTo: endId,
        )
        .get();

    final status = SplayTreeMap<String, bool>();
    for (int i = 0; i < daysBack; i++) {
      final date = _shiftDate(now, -i);
      status[formatDate(date)] = false;
    }

    for (final doc in querySnapshot.docs) {
      final data = doc.data();
      if (data['read'] == true) {
        status[doc.id] = true;
      }
    }

    // Fill gaps from read_logs where per-user reading docs are missing.
    final missingDateIds = <String>[];
    for (int i = 0; i < daysBack; i++) {
      final date = _shiftDate(now, -i);
      final id = formatDate(date);
      if (status[id] != true) {
        missingDateIds.add(id);
      }
    }

    if (missingDateIds.isNotEmpty) {
      // ⚡ Bolt: Use Future.wait to fetch all 30-item chunks concurrently to avoid N+1 query latency.
      final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
      for (var i = 0; i < missingDateIds.length; i += 30) {
        final batch = missingDateIds.sublist(
          i,
          i + 30 > missingDateIds.length ? missingDateIds.length : i + 30,
        );
        futures.add(
          firestore
              .collectionGroup('entries')
              .where(FieldPath.documentId, isEqualTo: uid)
              .where('dateId', whereIn: batch)
              .get(),
        );
      }

      final snapshots = await Future.wait(futures);
      for (final logsSnapshot in snapshots) {
        for (final doc in logsSnapshot.docs) {
          final dateId = doc.data()['dateId'] as String?;
          if (dateId != null) {
            status[dateId] = true;
          }
        }
      }
    }

    return status;
  }

  _SummaryComputation _computeStreakAndCredits({
    required DateTime today,
    required List<DateTime> sortedDates,
    required Set<String> readDateSet,
    required String Function(DateTime) formatDate,
    required String Function(DateTime) formatMonth,
  }) {
    final monthLedgers = <String, _MonthlyCreditLedger>{};
    if (sortedDates.isEmpty) {
      return _SummaryComputation(
        streak: 0,
        monthLedgers: monthLedgers,
        coveredDate: null,
        coveredViaGrace: false,
      );
    }

    final start = _dateOnly(sortedDates.first);
    final end = _dateOnly(today);
    if (start.isAfter(end)) {
      return _SummaryComputation(
        streak: 0,
        monthLedgers: monthLedgers,
        coveredDate: null,
        coveredViaGrace: false,
      );
    }

    final totalDays = end.difference(start).inDays;
    var currentStreak = 0;
    DateTime? lastCoveredDate;
    var lastCoverageUsedGrace = false;

    _MonthlyCreditLedger ensureLedger(DateTime date) {
      final key = formatMonth(date);
      return monthLedgers.putIfAbsent(
        key,
        () => _MonthlyCreditLedger(
          monthKey: key,
          monthStart: DateTime(date.year, date.month, 1),
        ),
      );
    }

    for (int offset = 0; offset <= totalDays; offset++) {
      final currentDate = _shiftDate(start, offset);
      final ledger = ensureLedger(currentDate);
      final key = formatDate(currentDate);
      final readToday = readDateSet.contains(key);
      final usedGraceCredit =
          !readToday && currentStreak > 0 && ledger.trySpend(currentDate);
      // Grace credits cover skipped days so the streak advances just like an
      // actual read, while bonus credits remain tied to real read activity.

      if (readToday || usedGraceCredit) {
        currentStreak += 1;
        lastCoveredDate = currentDate;
        lastCoverageUsedGrace = !readToday && usedGraceCredit;
        if (readToday && currentStreak % 15 == 0) {
          ledger.addBonusCredit(currentDate);
        }
      } else {
        // When neither a real read nor a grace credit covers the day, the
        // streak ends and a fresh count starts from the next actual read.
        currentStreak = 0;
      }
    }

    return _SummaryComputation(
      streak: currentStreak,
      monthLedgers: monthLedgers,
      coveredDate: lastCoveredDate,
      coveredViaGrace: lastCoverageUsedGrace,
    );
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _shiftDate(DateTime value, int days) {
  final normalized = _dateOnly(value);
  return DateTime(normalized.year, normalized.month, normalized.day + days);
}

class _SummaryComputation {
  const _SummaryComputation({
    required this.streak,
    required this.monthLedgers,
    required this.coveredDate,
    required this.coveredViaGrace,
  });

  final int streak;
  final Map<String, _MonthlyCreditLedger> monthLedgers;
  final DateTime? coveredDate;
  final bool coveredViaGrace;
}

class _MonthlyCreditLedger {
  _MonthlyCreditLedger({required this.monthKey, required DateTime monthStart})
      : _credits = Queue<_Credit>() {
    final start = _dateOnly(monthStart);
    _credits.add(_Credit(start));
    _credits.add(_Credit(start));
  }

  final String monthKey;
  final Queue<_Credit> _credits;
  int used = 0;

  void addBonusCredit(DateTime earnedOn) {
    _credits.add(_Credit(_dateOnly(earnedOn)));
  }

  bool trySpend(DateTime day) {
    final date = _dateOnly(day);
    for (final credit in _credits) {
      if (credit.used) {
        continue;
      }
      if (credit.earnedOn.isAfter(date)) {
        return false;
      }
      credit.used = true;
      used += 1;
      return true;
    }
    return false;
  }

  int available(DateTime asOf) {
    final date = _dateOnly(asOf);
    var count = 0;
    for (final credit in _credits) {
      if (credit.used) {
        continue;
      }
      if (credit.earnedOn.isAfter(date)) {
        continue;
      }
      count += 1;
    }
    return count;
  }
}

class _Credit {
  _Credit(DateTime earnedOn) : earnedOn = _dateOnly(earnedOn);

  final DateTime earnedOn;
  bool used = false;
}
