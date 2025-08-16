import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/error_logger.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../widgets/common_styles.dart';
import '../widgets/notification_button.dart';
import '../widgets/read_switch_tile.dart';
import '../widgets/success_animation.dart';
import '../widgets/menu_button.dart';
import '../widgets/week_streak_calendar.dart';
import '../widgets/month_streak_calendar.dart';
import '../services/achievement_service.dart';
import '../services/notification_service.dart';
import '../models/achievement.dart';
import '../theme/app_theme.dart';
import 'read_log_page.dart';

/// Landing page that displays reading progress and loads user data from
/// Firestore when the app starts.
class HomePage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  /// Cloud Functions instance used for first reader checks.
  final FirebaseFunctions? functions;

  /// Optional handler to mark the first reader for testing.
  final Future<Map<String, dynamic>?> Function({
    required String dateKey,
    required String uid,
  })? markFirstReader;

  HomePage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    this.functions,
    this.markFirstReader,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  bool _disposed = false;
  bool _readToday = false;

  /// Whether the page is currently fetching or toggling the read status.
  bool _toggleLoading = false;
  List<bool> _pastWeek = [];
  List<bool> _pastMonth = [];
  Set<DateTime> _readDates = {};

  @override
  void initState() {
    super.initState();
    _loadReadStatus();
  }

  /// Fetches today's read flag and calendar history from Firestore.
  /// Creates a user document if necessary and updates local state. When
  /// [showLoading] is true, a spinner is shown while the request is in flight.
  Future<void> _loadReadStatus({bool showLoading = true}) async {
    if (showLoading && !_disposed && mounted) {
      setState(() {
        _toggleLoading = true; // Start loading indicator.
      });
    }

    try {
      final user = widget.auth.currentUser;
      if (user == null) {
        if (showLoading && !_disposed && mounted) {
          setState(() {
            _toggleLoading = false;
          });
        }
        return;
      }

      final today = DateTime.now();
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final userDocRef = widget.firestore.collection('users').doc(user.uid);

      // Kick off all Firestore reads in parallel.
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
        // Reload only when user data is needed to create the document.
        await user.reload();
        final refreshedUser = widget.auth.currentUser;

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

      // Read today's status from the reading subcollection result.
      if (todayDoc.exists && todayDoc.data() != null) {
        final data = todayDoc.data()!;
        final hasRead = data.containsKey('read') ? data['read'] : false;
        if (!_disposed && mounted) {
          setState(() {
            _readToday = hasRead;
          });
        }
      }

      // Load calendar data from summary doc.
      final data = summaryDoc.data() ?? {};
      final weekDates = List<String>.from(data['pastWeekReadDates'] ?? []);
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
      final monthDates = List<String>.from(data['pastMonthReadDates'] ?? []);
      final now = DateTime.now();
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      for (int i = 1; i <= daysInMonth; i++) {
        final key =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${i.toString().padLeft(2, '0')}';
        savedMonth.add(monthDates.contains(key));
      }

      if (weekDates.isEmpty) {
        // Backfill the past week by querying reading documents directly.
        final weekStatus = await _getReadStatusForRange(7);
        savedWeek.clear();
        for (int i = 0; i < 7; i++) {
          final date = sunday.add(Duration(days: i));
          final key =
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          savedWeek.add(weekStatus[key] ?? false);
        }
      }
      if (monthDates.isEmpty) {
        // Backfill the past month similarly.
        final monthStatus = await _getReadStatusForRange(30);
        savedMonth.clear();
        for (int i = 1; i <= daysInMonth; i++) {
          final key =
              '${now.year}-${now.month.toString().padLeft(2, '0')}-${i.toString().padLeft(2, '0')}';
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
          readDates.add(DateTime(now.year, now.month, i + 1));
        }
      }

      if (!_disposed && mounted) {
        // Update state with fetched data.
        setState(() {
          _pastWeek = savedWeek;
          _pastMonth = savedMonth;
          _readDates = readDates;
        });
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Error loading status: $e');
      }
      ErrorLogger.log(e, st);
    } finally {
      if (showLoading && !_disposed && mounted) {
        setState(() {
          _toggleLoading = false; // Always stop loading.
        });
      }
    }
  }

  /// Returns a map indicating whether the user has read on each of the past
  /// [daysBack] days. The keys are formatted as `yyyy-MM-dd`.
  Future<Map<String, bool>> _getReadStatusForRange(int daysBack) async {
    final user = widget.auth.currentUser;
    if (user == null) return {};

    final userDocRef = widget.firestore.collection('users').doc(user.uid);
    final readingCollection = userDocRef.collection('reading');

    final now = DateTime.now();
    final futures = <Future<MapEntry<String, bool>>>[];

    for (int i = 0; i < daysBack; i++) {
      final date = now.subtract(Duration(days: i));
      final docId =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final key = docId;

      futures.add(
        readingCollection.doc(docId).get().then((doc) {
          final read = doc.exists && doc.data()?['read'] == true;
          return MapEntry(key, read);
        }),
      );
    }

    final results = await Future.wait(futures);
    return Map.fromEntries(results);
  }

  /// Cleans and updates the cached summary document without scanning the entire
  /// reading collection. Removes outdated entries, ensures the summary document
  /// exists and resets the streak if a day was missed.
  Future<void> _updateSummary() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    try {
      final userDocRef = widget.firestore.collection('users').doc(user.uid);
      final summaryDocRef = userDocRef.collection('summary').doc('data');
      final doc = await summaryDocRef.get();
      final data = doc.data() ?? {};

      final today = DateTime.now();
      String formatDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      // Query recent reading documents to rebuild cached arrays.
      final weekStatus = await _getReadStatusForRange(7);
      final monthStatus = await _getReadStatusForRange(30);

      final pastWeekReadDates =
          weekStatus.entries.where((e) => e.value).map((e) => e.key).toList();
      final pastMonthReadDates =
          monthStatus.entries.where((e) => e.value).map((e) => e.key).toList();

      // Recalculate current streak based on most recent reads.
      int streak = 0;
      for (int i = 0; i < 30; i++) {
        final key = formatDate(today.subtract(Duration(days: i)));
        if (monthStatus[key] == true) {
          streak += 1;
        } else {
          break;
        }
      }

      int totalReadDays =
          (data['totalReadDays'] is int) ? data['totalReadDays'] : 0;
      int longestStreak =
          (data['longestStreak'] is int) ? data['longestStreak'] : 0;
      if (streak > longestStreak) {
        longestStreak = streak;
      }

      await summaryDocRef.set({
        'streak': streak,
        'pastWeekReadDates': pastWeekReadDates,
        'pastMonthReadDates': pastMonthReadDates,
        'totalReadDays': totalReadDays,
        'longestStreak': longestStreak,
      }, SetOptions(merge: true));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to update summary: $e');
      }
      ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update summary. Please try again.'),
          ),
        );
        unawaited(_loadReadStatus(showLoading: false));
      }
    }
  }

  /// Marks the current day as read. Optimistically updates local state and
  /// writes the change to Firestore, rolling back on failure.
  Future<void> _toggleReadStatus() async {
    if (_readToday) return;

    final user = widget.auth.currentUser;
    if (user == null) return;

    // Reload user before writing to Firestore.
    await user.reload();
    final refreshedUser = widget.auth.currentUser;

    // Preserve current state in case we need to revert on error.
    final prevWeek = List<bool>.from(_pastWeek);
    final prevMonth = List<bool>.from(_pastMonth);
    final prevReadDates = Set<DateTime>.from(_readDates);

    final today = DateTime.now();
    final weekIndex = today.weekday % 7;
    final monthIndex = today.day - 1;
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;

    if (!_disposed && mounted) {
      setState(() {
        // Optimistically mark today as read in local state.
        _readToday = true;
        if (_pastWeek.length < 7) {
          _pastWeek = List<bool>.generate(
            7,
            (i) => i < _pastWeek.length ? _pastWeek[i] : false,
          );
        }
        _pastWeek[weekIndex] = true;
        if (_pastMonth.length < daysInMonth) {
          _pastMonth = List<bool>.generate(
            daysInMonth,
            (i) => i < _pastMonth.length ? _pastMonth[i] : false,
          );
        }
        _pastMonth[monthIndex] = true;
        _readDates.add(DateTime(today.year, today.month, today.day));
      });
    }

    try {
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      await ReadLogPage.writeReadLogEntry(
        refreshedUser ?? user,
        firestore: widget.firestore,
        functions: widget.functions,
        markFirstReader: widget.markFirstReader,
        dateProvider: () => today,
      );

      await widget.firestore
          .collection('users')
          .doc(user.uid)
          .collection('reading')
          .doc(dateKey)
          .set({
        'read': true,
      }, SetOptions(merge: true)); // Mark read in Firestore.

      // Update summary collection (lightweight update)
      await _updateSummaryWithToday();

      if (!_disposed && mounted) {
        SuccessAnimation.show(context);
      }

      unawaited(_loadReadStatus(showLoading: false));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to mark reading: $e');
      }
      ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        // Revert to previous state and notify the user.
        setState(() {
          _readToday = false;
          _pastWeek = prevWeek;
          _pastMonth = prevMonth;
          _readDates = prevReadDates;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to mark reading. Please try again.'),
          ),
        );
      }
    }
  }

  /// Lightweight summary update for today's read. Updates streak and cached
  /// read-date arrays without recomputing historical data.
  Future<void> _updateSummaryWithToday() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    try {
      final userDocRef = widget.firestore.collection('users').doc(user.uid);
      final summaryDocRef = userDocRef.collection('summary').doc('data');
      // Load existing summary values to increment cached fields.
      final doc = await summaryDocRef.get();
      final data = doc.data() ?? {};

      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      final yesterdayDateKey =
          '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

      final yesterdayDoc =
          await userDocRef.collection('reading').doc(yesterdayDateKey).get();

      int streak = (data['streak'] is int) ? data['streak'] : 0;
      if (yesterdayDoc.exists && yesterdayDoc.data()?['read'] == true) {
        streak += 1;
      } else {
        streak = 1; // Reset streak if yesterday was missed
      }

      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final pastWeekReadDates = List<String>.from(
        data['pastWeekReadDates'] ?? [],
      );
      if (!pastWeekReadDates.contains(dateKey)) {
        pastWeekReadDates.add(dateKey);
        if (pastWeekReadDates.length > 7) {
          pastWeekReadDates.removeRange(0, pastWeekReadDates.length - 7);
        }
      }

      final pastMonthReadDates = List<String>.from(
        data['pastMonthReadDates'] ?? [],
      );
      if (!pastMonthReadDates.contains(dateKey)) {
        pastMonthReadDates.add(dateKey);
        if (pastMonthReadDates.length > 30) {
          pastMonthReadDates.removeRange(0, pastMonthReadDates.length - 30);
        }
      }

      int totalReadDays =
          (data['totalReadDays'] is int) ? data['totalReadDays'] : 0;
      totalReadDays += 1;

      int longestStreak =
          (data['longestStreak'] is int) ? data['longestStreak'] : streak;
      if (streak > longestStreak) {
        longestStreak = streak;
      }

      await summaryDocRef.set({
        'streak': streak,
        'pastWeekReadDates': pastWeekReadDates,
        'pastMonthReadDates': pastMonthReadDates,
        'totalReadDays': totalReadDays,
        'longestStreak': longestStreak,
      }, SetOptions(merge: true)); // Persist updated summary.

      await _checkAchievements(user.uid, streak, totalReadDays);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to update summary with today: \$e');
      }
      ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update summary. Please try again.'),
          ),
        );
        unawaited(_loadReadStatus(showLoading: false));
      }
    }
  }

  /// Unlocks achievements based on the user's streak and total read days.
  Future<void> _checkAchievements(
    String uid,
    int streak,
    int totalReadDays,
  ) async {
    try {
      final service = AchievementService(firestore: widget.firestore);
      if (streak >= 7) {
        await service.unlockAchievement(
          uid,
          Achievement(
            id: 'streak7',
            title: '7-Day Streak',
            type: 'streak',
            dateUnlocked: DateTime.now(),
          ),
        );
      }
      if (totalReadDays >= 30) {
        await service.unlockAchievement(
          uid,
          Achievement(
            id: 'days30',
            title: '30 Days Read',
            type: 'days',
            dateUnlocked: DateTime.now(),
          ),
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to unlock achievements: $e');
      }
      ErrorLogger.log(e, st);
    }
  }

  /// Adds a like entry for today's reading document.
  Future<void> likeReading() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final userDocRef = widget.firestore.collection('users').doc(user.uid);

    try {
      await userDocRef
          .collection('reading')
          .doc(dateKey)
          .collection('likes')
          .doc(user.uid)
          .set({'timestamp': Timestamp.now()}); // Record like with timestamp.
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to like reading: $e');
      }
      ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to like reading. Please try again.'),
          ),
        );
      }
    }
  }

  /// Removes the current user's like from today's reading document.
  Future<void> unlikeReading() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final userDocRef = widget.firestore.collection('users').doc(user.uid);

    try {
      await userDocRef
          .collection('reading')
          .doc(dateKey)
          .collection('likes')
          .doc(user.uid)
          .delete();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to unlike reading: $e');
      }
      ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to unlike reading. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Bible Reading Challenge',
          style: CommonStyles.appBarTitleText,
        ),
        backgroundColor: AppTheme.backgroundColor,
        leading: const MenuButton(),
        automaticallyImplyLeading: false,
        actions: [
          if (widget.auth.currentUser != null)
            NotificationButton(
              service: NotificationService(firestore: widget.firestore),
              auth: widget.auth,
            ),
        ],
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: _buildMainContent(),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    if (widget.auth.currentUser == null) {
      return Center(
        child: Text(
          'User not signed in.',
          style: AppTextStyles.subtitle.copyWith(color: Colors.white70),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        try {
          await widget.auth.currentUser?.reload();
          final googleAccount = await GoogleSignIn().signInSilently();
          final firebaseUser = widget.auth.currentUser;
          if (googleAccount != null && firebaseUser != null) {
            await firebaseUser.updateDisplayName(googleAccount.displayName);
            await firebaseUser.reload();
          }
          await _updateSummary();
          await _loadReadStatus();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Refreshed successfully')),
          );
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('Refresh failed: \$e');
          }
          ErrorLogger.log(e, st);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to refresh data. Please try again.'),
            ),
          );
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.only(
            top: 16.0,
            bottom: 48,
            left: 16,
            right: 16,
          ),
          child: Column(
            children: [
              CommonStyles.buildCard(
                child: _toggleLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Mark today as read'),
                          ReadSwitchTile(
                            value: _readToday,
                            onChanged: _readToday
                                ? null
                                : (value) => _toggleReadStatus(),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              IgnorePointer(
                child: WeekStreakCalendar(
                  readDates: _readDates,
                  sunday: DateTime.now().subtract(
                    Duration(days: DateTime.now().weekday % 7),
                  ),
                  showNavigation: false,
                ),
              ),
              const SizedBox(height: 16),
              IgnorePointer(
                child: MonthStreakCalendar(
                  readDates: _readDates,
                  month: DateTime(DateTime.now().year, DateTime.now().month),
                  showNavigation: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;
}
