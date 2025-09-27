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

  /// Creates a [ReadingStatus].
  const ReadingStatus({
    required this.readToday,
    required this.pastWeek,
    required this.pastMonth,
    required this.readDates,
  });
}

/// Summary statistics returned after updating the summary document.
class SummaryStats {
  /// Consecutive days the user has read up to today.
  final int streak;

  /// Total number of days the user has read.
  final int totalReadDays;

  /// Creates [SummaryStats].
  const SummaryStats({required this.streak, required this.totalReadDays});
}

/// Service responsible for reading status and summary calculations.
class ReadingStatusService {
  /// Firestore instance used for database operations.
  final FirebaseFirestore firestore;

  /// Authentication instance for the current user.
  final FirebaseAuth auth;

  /// Creates a [ReadingStatusService] using default Firebase instances.
  ReadingStatusService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance;

  /// Fetches today's read flag and calendar history. Ensures the user
  /// document exists and backfills missing calendar entries.
  Future<ReadingStatus> fetchStatus() async {
    final user = auth.currentUser;
    if (user == null) {
      return const ReadingStatus(
        readToday: false,
        pastWeek: [],
        pastMonth: [],
        readDates: {},
      );
    }

    try {
      final today = DateTime.now();
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
        final friendRequestsSentCollection =
            userDocRef.collection('friendRequestsSent');

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
      final sunday = today.subtract(
        Duration(days: currentWeekday % 7),
      ); // get this week's Sunday
      for (int i = 0; i < 7; i++) {
        final date = sunday.add(Duration(days: i)); // Sunday to Saturday
        final key =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        savedWeek[i] = weekDates.contains(key);
      }

      final savedMonth = <bool>[];
      var monthDates = List<String>.from(data['pastMonthReadDates'] ?? []);
      monthDates = monthDates.where((d) {
        final parsed = DateTime.tryParse(d);
        if (parsed == null) return false;
        final diff = today.difference(parsed).inDays;
        return diff >= 0 && diff < 30;
      }).toList();
      final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
      for (int i = 1; i <= daysInMonth; i++) {
        final key =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${i.toString().padLeft(2, '0')}';
        savedMonth.add(monthDates.contains(key));
      }

      if (weekDates.length < 7) {
        // Backfill the past week by querying reading documents directly.
        final weekStatus = await _getReadStatusForRange(user.uid, 7);
        savedWeek.clear();
        for (int i = 0; i < 7; i++) {
          final date = sunday.add(Duration(days: i));
          final key =
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          savedWeek.add(weekStatus[key] ?? false);
        }
      }
      if (monthDates.length < 30) {
        // Backfill the past month similarly.
        final monthStatus = await _getReadStatusForRange(user.uid, 30);
        savedMonth.clear();
        for (int i = 1; i <= daysInMonth; i++) {
          final key =
              '${today.year}-${today.month.toString().padLeft(2, '0')}-${i.toString().padLeft(2, '0')}';
          savedMonth.add(monthStatus[key] ?? false);
        }
      }

      final readDates = <DateTime>{};
      for (int i = 0; i < savedWeek.length; i++) {
        if (savedWeek[i]) {
          final date = sunday.add(Duration(days: i));
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
    if (user == null) {
      return const SummaryStats(streak: 0, totalReadDays: 0);
    }

    try {
      final userDocRef = firestore.collection('users').doc(user.uid);
      final summaryDocRef = userDocRef.collection('summary').doc('data');

      final today = DateTime.now();
      String formatDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      // Query recent reading documents to rebuild cached arrays.
      final weekStatus = await _getReadStatusForRange(user.uid, 7);
      final monthStatus = await _getReadStatusForRange(user.uid, 30);

      final pastWeekReadDates =
          weekStatus.entries.where((e) => e.value).map((e) => e.key).toList();
      final pastMonthReadDates =
          monthStatus.entries.where((e) => e.value).map((e) => e.key).toList();

      // Fetch all reading entries to recompute aggregate counters.
      final readingSnapshot = await userDocRef.collection('reading').get();
      final readDateSet = <String>{};
      for (final readDoc in readingSnapshot.docs) {
        final data = readDoc.data();
        if (data['read'] == true) {
          readDateSet.add(readDoc.id);
        }
      }

      // Backfill from read_logs for recent history where user/reading docs are missing.
      // This helps avoid showing a 1-day streak when users only posted to the feed.
      for (int i = 0; i < 90; i++) {
        final d = DateTime(today.year, today.month, today.day)
            .subtract(Duration(days: i));
        final key = formatDate(d);
        if (readDateSet.contains(key)) continue;
        try {
          final entry = await firestore
              .collection('read_logs')
              .doc(key)
              .collection('entries')
              .doc(user.uid)
              .get();
          if (entry.exists) {
            readDateSet.add(key);
          }
        } catch (_) {
          // Ignore failures; best-effort backfill.
        }
      }

      final totalReadDays = readDateSet.length;

      // Recalculate current streak based on most recent consecutive reads.
      int streak = 0;
      var cursor = DateTime(today.year, today.month, today.day);
      while (readDateSet.contains(formatDate(cursor))) {
        streak += 1;
        cursor = cursor.subtract(const Duration(days: 1));
      }

      // Determine the longest streak across all recorded reads.
      int longestStreak = 0;
      if (readDateSet.isNotEmpty) {
        final sortedDates = readDateSet.map((d) => DateTime.parse(d)).toList()
          ..sort();
        int current = 1;
        longestStreak = 1;
        for (int i = 1; i < sortedDates.length; i++) {
          if (sortedDates[i].difference(sortedDates[i - 1]).inDays == 1) {
            current += 1;
          } else {
            current = 1;
          }
          if (current > longestStreak) {
            longestStreak = current;
          }
        }
      }

      await summaryDocRef.set({
        'streak': streak,
        'pastWeekReadDates': pastWeekReadDates,
        'pastMonthReadDates': pastMonthReadDates,
        'totalReadDays': totalReadDays,
        'longestStreak': longestStreak,
      }, SetOptions(merge: true));

      return SummaryStats(streak: streak, totalReadDays: totalReadDays);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to update summary: $e');
      }
      ErrorLogger.log(e, st);
      rethrow;
    }
  }

  Future<Map<String, bool>> _getReadStatusForRange(
      String uid, int daysBack) async {
    final userDocRef = firestore.collection('users').doc(uid);
    final readingCollection = userDocRef.collection('reading');

    final now = DateTime.now();
    String formatDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final startDate = now.subtract(Duration(days: daysBack - 1));
    final startId = formatDate(startDate);
    final endId = formatDate(now);

    final querySnapshot = await readingCollection
        .where(FieldPath.documentId,
            isGreaterThanOrEqualTo: startId, isLessThanOrEqualTo: endId)
        .get();

    final status = <String, bool>{};
    for (int i = 0; i < daysBack; i++) {
      final date = now.subtract(Duration(days: i));
      status[formatDate(date)] = false;
    }

    for (final doc in querySnapshot.docs) {
      final data = doc.data();
      if (data['read'] == true) {
        status[doc.id] = true;
      }
    }

    // Fill gaps from read_logs where per-user reading docs are missing.
    for (int i = 0; i < daysBack; i++) {
      final date = now.subtract(Duration(days: i));
      final id = formatDate(date);
      if (status[id] == true) continue;
      try {
        final entry = await firestore
            .collection('read_logs')
            .doc(id)
            .collection('entries')
            .doc(uid)
            .get();
        if (entry.exists) {
          status[id] = true;
        }
      } catch (_) {
        // ignore
      }
    }

    return status;
  }
}
