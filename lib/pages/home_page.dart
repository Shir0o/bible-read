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
import '../widgets/menu_button.dart';
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
  int _streak = 0;
  List<bool> _pastWeek = [];
  List<bool> _pastMonth = [];

  @override
  void initState() {
    super.initState();
    _loadReadStatus();
  }

  /// Fetches today's read flag, streak, and calendar history from Firestore.
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
      await widget.auth.currentUser?.reload();
      final refreshedUser = widget.auth.currentUser;
      if (user == null) {
        // If user is null, stop loading and return
        if (showLoading && !_disposed && mounted) {
          setState(() {
            _toggleLoading = false;
          });
        }
        return;
      }

      final today = DateTime.now();
      final dateKey = '${today.year}-${today.month}-${today.day}';

      final userDocRef = widget.firestore.collection('users').doc(user.uid);
      final userDoc = await userDocRef.get();
      if (!userDoc.exists) {
        // Create the user document with basic profile fields.
        await userDocRef.set({
          'name': refreshedUser?.displayName ?? '',
          'email': refreshedUser?.email?.toLowerCase() ?? '',
        });

        // Initialize subcollections so later queries succeed.
        final friendsCollection = userDocRef.collection('friends');
        final friendRequestsSentCollection = userDocRef.collection(
          'friendRequestsSent',
        );
        await friendsCollection.doc('init').set({
          'status': 'placeholder',
          'timestamp': Timestamp.now(),
        }, SetOptions(merge: true));
        await friendRequestsSentCollection.doc('init').set({
          'status': 'placeholder',
          'timestamp': Timestamp.now(),
        }, SetOptions(merge: true));
      }

      // Read today's status from the reading subcollection.
      final doc = await userDocRef.collection('reading').doc(dateKey).get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final hasRead = data.containsKey('read') ? data['read'] : false;
        if (!_disposed && mounted) {
          setState(() {
            _readToday = hasRead;
          });
        }
      }

      // Always load streak from summary doc (no fallback to recalc).
      final summaryDoc =
          await userDocRef.collection('summary').doc('data').get();
      final data = summaryDoc.data() ?? {};
      int streak = data['streak'] ?? 0;

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
        savedWeek.addAll(weekStatus);
      }
      if (monthDates.isEmpty) {
        // Backfill the past month similarly.
        final monthStatus = await _getReadStatusForRange(30);
        savedMonth.clear();
        savedMonth.addAll(monthStatus);
      }

      if (!_disposed && mounted) {
        // Update state with fetched data.
        setState(() {
          _streak = streak;
          _pastWeek = savedWeek;
          _pastMonth = savedMonth;
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

  /// Returns a list indicating whether the user has read on each of the past
  /// [daysBack] days. Queries the `reading` subcollection one document per day.
  Future<List<bool>> _getReadStatusForRange(int daysBack) async {
    final user = widget.auth.currentUser;
    if (user == null) return [];

    final userDocRef = widget.firestore.collection('users').doc(user.uid);
    final readingCollection = userDocRef.collection('reading');

    List<bool> statuses = [];

    for (int i = 0; i < daysBack; i++) {
      final date = DateTime.now().subtract(Duration(days: i));
      final key = '${date.year}-${date.month}-${date.day}';
      final doc = await readingCollection.doc(key).get();
      // Each document has a `read` flag; default to false if missing.
      statuses.add(doc.exists && doc.data()?['read'] == true);
    }

    return statuses.reversed.toList();
  }

  /// Recalculates the streak, past-week, and past-month data and writes to summary collection.
  Future<void> _updateSummary() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    try {
      final userDocRef = widget.firestore.collection('users').doc(user.uid);
      final readingCollection = userDocRef.collection('reading');

      // Calculate streak, starting from today and counting backward in time
      int streak = 0;
      while (true) {
        final date = DateTime.now().subtract(Duration(days: streak));
        final key = '${date.year}-${date.month}-${date.day}';
        final doc = await readingCollection.doc(key).get();
        if (doc.exists && doc.data()?['read'] == true) {
          streak++;
        } else {
          break;
        }
      }

      // Past 7 days
      final pastWeekStatus = await _getReadStatusForRange(7);
      final pastWeekReadDates = <String>[];
      for (int i = 0; i < pastWeekStatus.length; i++) {
        if (pastWeekStatus[i]) {
          final day = DateTime.now().subtract(
            Duration(days: pastWeekStatus.length - 1 - i),
          );
          pastWeekReadDates.add(
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
          );
        }
      }

      // Past 30 days
      final pastMonthStatus = await _getReadStatusForRange(30);
      final pastMonthReadDates = <String>[];
      for (int i = 0; i < pastMonthStatus.length; i++) {
        if (pastMonthStatus[i]) {
          final day = DateTime.now().subtract(
            Duration(days: pastMonthStatus.length - 1 - i),
          );
          pastMonthReadDates.add(
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
          );
        }
      }

      // Write to summary doc (store only cached streak, past week, past month)
      await userDocRef.collection('summary').doc('data').set({
        'streak': streak,
        'pastWeekReadDates': pastWeekReadDates,
        'pastMonthReadDates': pastMonthReadDates,
      }, SetOptions(merge: true));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to update summary: \$e');
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
    final prevStreak = _streak;
    final prevWeek = List<bool>.from(_pastWeek);
    final prevMonth = List<bool>.from(_pastMonth);

    final today = DateTime.now();
    final weekIndex = today.weekday % 7;
    final monthIndex = today.day - 1;
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;

    if (!_disposed && mounted) {
      setState(() {
        // Optimistically mark today as read in local state.
        _readToday = true;
        _streak += 1;
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
      });
    }

    try {
      final dateKey = '${today.year}-${today.month}-${today.day}';
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
          _streak = prevStreak;
          _pastWeek = prevWeek;
          _pastMonth = prevMonth;
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
          '${yesterday.year}-${yesterday.month}-${yesterday.day}';

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

      await summaryDocRef.set({
        'streak': streak,
        'pastWeekReadDates': pastWeekReadDates,
        'pastMonthReadDates': pastMonthReadDates,
        'totalReadDays': totalReadDays,
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
    final dateKey = '${today.year}-${today.month}-${today.day}';
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
    final dateKey = '${today.year}-${today.month}-${today.day}';
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.local_fire_department,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Streak: $_streak day${_streak == 1 ? '' : 's'}",
                      style: AppTextStyles.subtitle,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
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
                    : ReadSwitchTile(
                        value: _readToday,
                        onChanged:
                            _readToday ? null : (value) => _toggleReadStatus(),
                        label: 'Bible Read Today',
                      ),
              ),
              const SizedBox(height: 16),
              CommonStyles.buildCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Builder(
                      builder: (context) {
                        final now = DateTime.now();
                        final sunday = now.subtract(
                          Duration(days: now.weekday % 7),
                        );
                        final weekOf = '${sunday.month}/${sunday.day}';
                        const days = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

                        return Column(
                          children: [
                            Text(
                              'Week of $weekOf',
                              style: AppTextStyles.body.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(7, (i) {
                                final weekData = _pastWeek.length == 7
                                    ? _pastWeek
                                    : List<bool>.generate(
                                        7,
                                        (i) => i < _pastWeek.length
                                            ? _pastWeek[i]
                                            : false,
                                      );
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        days[i],
                                        style: AppTextStyles.body.copyWith(
                                          fontSize: 10,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Icon(
                                        weekData[i]
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        color: weekData[i]
                                            ? Colors.green
                                            : Colors.grey,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CommonStyles.buildCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "${DateTime.now().year} – ${_monthName(DateTime.now().month)}",
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Table(
                          defaultColumnWidth: const FixedColumnWidth(32),
                          children: [
                            TableRow(
                              children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                                  .map(
                                    (d) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: Center(
                                        child: Text(
                                          d,
                                          style: AppTextStyles.body.copyWith(
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                            ..._buildMonthCalendar(),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds calendar rows for the current month based on `_pastMonth` data.
  List<TableRow> _buildMonthCalendar() {
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final totalDays = DateTime(now.year, now.month + 1, 0).day;
    final weekdayOffset = firstDay.weekday % 7;

    final rows = <TableRow>[];
    List<Widget> currentRow = List.filled(7, const SizedBox.shrink());

    for (int i = 0; i < weekdayOffset; i++) {
      currentRow[i] = const SizedBox.shrink();
    }

    for (int day = 1; day <= totalDays; day++) {
      int index = weekdayOffset + day - 1;
      int weekRow = index ~/ 7;
      int weekdayIndex = index % 7;

      if (rows.length <= weekRow) {
        rows.add(TableRow(children: List.filled(7, const SizedBox.shrink())));
      }

      final filled = _pastMonth.length >= day && _pastMonth[day - 1];
      rows[weekRow].children[weekdayIndex] = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Icon(
            filled ? Icons.circle : Icons.circle_outlined,
            size: 12,
            color: filled ? Colors.green : Colors.grey,
          ),
        ),
      );
    }

    return rows;
  }

  /// Returns a month name for the given [month] number.
  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;
}
