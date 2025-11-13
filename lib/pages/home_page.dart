import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/achievement.dart';
import '../services/achievement_service.dart';
import '../services/error_logger.dart';
import '../services/friendly_streak_service.dart';
import '../services/google_sign_in_factory.dart';
import '../services/notification_service.dart';
import '../services/reading_status_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_styles.dart';
import '../widgets/friendly_streak_banner.dart';
import '../widgets/notification_button.dart';
import '../widgets/read_status_section.dart';
import 'read_log_page.dart';
import 'streak_history_page.dart';

/// Landing page that displays reading progress and loads user data from
/// Firestore when the app starts.
class HomePage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final GoogleSignIn Function() googleSignInProvider;

  /// Cloud Functions instance used for first reader checks.
  final FirebaseFunctions? functions;

  /// Optional handler to mark the first reader for testing.
  final Future<Map<String, dynamic>?> Function({
    required String dateKey,
    required String uid,
  })?
  markFirstReader;

  HomePage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    this.functions,
    this.markFirstReader,
    ReadingStatusService? readingStatusService,
    VibrationService? vibrationService,
    GoogleSignIn Function()? googleSignInProvider,
    FriendlyStreakService? friendlyStreakService,
  }) : firestore = firestore ?? FirebaseFirestore.instance,
       auth = auth ?? FirebaseAuth.instance,
       readingStatusService =
           readingStatusService ??
           ReadingStatusService(firestore: firestore, auth: auth),
       vibrationService = vibrationService ?? const VibrationService(),
       googleSignInProvider = googleSignInProvider ?? createGoogleSignIn,
       friendlyStreakService =
           friendlyStreakService ?? FriendlyStreakService(firestore: firestore);

  /// Service for loading and updating reading status.
  final ReadingStatusService readingStatusService;

  /// Service used for read-toggle haptics.
  final VibrationService vibrationService;

  /// Service responsible for loading friends' streaks.
  final FriendlyStreakService friendlyStreakService;

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
  int? _streakFreezesLeft;
  int? _friendsTopStreak;
  bool _friendStreakLoading = false;

  @override
  void initState() {
    super.initState();
    _loadReadStatus();
    _loadFriendlyStreak();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth) {
      unawaited(_loadReadStatus());
      unawaited(_loadFriendlyStreak());
    }
  }

  /// Fetches today's read flag and calendar history.
  Future<void> _loadReadStatus({bool showLoading = true}) async {
    if (showLoading && !_disposed && mounted) {
      setState(() {
        _toggleLoading = true; // Start loading indicator.
      });
    }

    try {
      final status = await widget.readingStatusService.fetchStatus();
      if (!_disposed && mounted) {
        setState(() {
          _readToday = status.readToday;
          _pastWeek = status.pastWeek;
          _pastMonth = status.pastMonth;
          _readDates = status.readDates;
          _streakFreezesLeft = status.graceCreditsAvailable;
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

  Future<void> _loadFriendlyStreak({bool showLoading = true}) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) {
      if (!_disposed && mounted) {
        setState(() {
          _friendsTopStreak = null;
          _friendStreakLoading = false;
        });
      }
      return;
    }

    if (showLoading && !_disposed && mounted) {
      setState(() {
        _friendStreakLoading = true;
      });
    }

    final streak = await widget.friendlyStreakService.fetchTopStreak(uid);
    if (!_disposed && mounted) {
      setState(() {
        _friendsTopStreak = streak;
        _friendStreakLoading = false;
      });
    }
  }

  /// Cleans and updates the cached summary document without scanning the entire
  /// reading collection. Removes outdated entries, ensures the summary document
  /// exists and resets the streak if a day was missed.
  Future<void> _updateSummary() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    try {
      final stats = await widget.readingStatusService.updateSummary();
      await _checkAchievements(user.uid, stats.streak, stats.totalReadDays);
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

      // Removed success animation after backend success to reduce noise.

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

  /// Recomputes summary data after marking today as read. Delegates to
  /// [ReadingStatusService.updateSummary], which applies the shared
  /// chronological grace-credit accounting used across the app.
  Future<void> _updateSummaryWithToday() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    try {
      final stats = await widget.readingStatusService.updateSummary();
      await _checkAchievements(user.uid, stats.streak, stats.totalReadDays);
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
      if (streak >= 30) {
        await service.unlockAchievement(
          uid,
          Achievement(
            id: 'streak30',
            title: '30-Day Streak',
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
        title: const Text('Reading Hub', style: CommonStyles.appBarTitleText),
        backgroundColor: AppTheme.backgroundColor,
        automaticallyImplyLeading: false,
        actions: [
          NotificationButton(
            service: NotificationService(firestore: widget.firestore),
            auth: widget.auth,
            vibrationService: widget.vibrationService,
          ),
        ],
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: _buildMainContent(context),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context) {
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
        final messenger = ScaffoldMessenger.of(context);
        try {
          await widget.auth.currentUser?.reload();
          final googleSignIn = widget.googleSignInProvider();
          final googleAccount = await googleSignIn.signInSilently();
          final firebaseUser = widget.auth.currentUser;
          if (googleAccount != null && firebaseUser != null) {
            await firebaseUser.updateDisplayName(googleAccount.displayName);
            await firebaseUser.reload();
          }
          await _updateSummary();
          await _loadReadStatus();
          await _loadFriendlyStreak(showLoading: false);
          if (!mounted) return;
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(content: Text('Refreshed successfully')),
            );
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('Refresh failed: \$e');
          }
          ErrorLogger.log(e, st);
          if (!mounted) return;
          messenger.showSnackBar(
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReadStatusSection(
                toggleLoading: _toggleLoading,
                readToday: _readToday,
                onToggle: _toggleReadStatus,
                readDates: _readDates,
                streakFreezesLeft: _streakFreezesLeft,
                vibrationService: widget.vibrationService,
              ),
              if (_friendStreakLoading || _friendsTopStreak != null)
                FriendlyStreakBanner(
                  streak: _friendsTopStreak,
                  isLoading: _friendStreakLoading,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => StreakHistoryPage(
                          firestore: widget.firestore,
                          auth: widget.auth,
                        ),
                      ),
                    );
                  },
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
