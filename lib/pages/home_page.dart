import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/achievement.dart';
import '../services/achievement_service.dart';
import '../services/book_achievement_refresher.dart';
import '../services/error_logger.dart';
import '../services/friend_streak_link_service.dart';
import '../services/friendly_streak_service.dart';
import '../services/google_sign_in_factory.dart';
import '../services/group_book_achievement_service.dart';
import '../services/reading_plan_service.dart';
import '../services/reading_status_service.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart'; // Kept for AppTextStyles if used, or verify usage. Check minimal usage.
import '../widgets/skeleton_loader.dart';
import '../widgets/skeletons/home_page_skeleton.dart';
import 'read_log_page.dart';
import '../widgets/profile_button.dart';

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
  })? markFirstReader;

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
    AchievementService? achievementService,
    GroupBookAchievementService? groupBookAchievementService,
    FriendStreakLinkService? friendStreakLinkService,
    ReadingPlanService? readingPlanService,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        readingStatusService = readingStatusService ??
            ReadingStatusService(firestore: firestore ?? FirebaseFirestore.instance, auth: auth ?? FirebaseAuth.instance),
        readingPlanService = readingPlanService ??
            ReadingPlanService(firestore: firestore ?? FirebaseFirestore.instance),
        vibrationService = vibrationService ?? const VibrationService(),
        googleSignInProvider = googleSignInProvider ?? createGoogleSignIn,
        friendlyStreakService = friendlyStreakService ??
            FriendlyStreakService(firestore: firestore),
        achievementService =
            achievementService ?? AchievementService(firestore: firestore),
        groupBookAchievementService = groupBookAchievementService ??
            GroupBookAchievementService(firestore: firestore),
        friendStreakLinkService = friendStreakLinkService ??
            FriendStreakLinkService(firestore: firestore);

  /// Service for loading and updating reading status.
  final ReadingStatusService readingStatusService;

  /// Service used for read-toggle haptics.
  final VibrationService vibrationService;

  /// Service responsible for loading friends' streaks.
  final FriendlyStreakService friendlyStreakService;

  /// Service responsible for unlocking achievements.
  final AchievementService achievementService;

  /// Aggregates reading progress across groups for book badges.
  final GroupBookAchievementService groupBookAchievementService;

  /// Service that fans read coverage events out to friend streak links.
  final FriendStreakLinkService friendStreakLinkService;

  /// Service for managing reading plans.
  final ReadingPlanService readingPlanService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  bool _disposed = false;
  bool _readToday = false;

  /// Whether the page is currently fetching or toggling the read status.
  bool _toggleLoading = false;
  /// Whether the page is currently performing its initial data fetch.
  bool _initialLoading = true;
  List<bool> _pastWeek = [];
  List<bool> _pastMonth = [];
  Set<DateTime> _readDates = {};
  int? _streakFreezesLeft;
  int _currentStreak = 0;
  FriendlyStreakLinksSummary? _friendStreaks;
  bool _friendStreakLoading = false;
  late BookAchievementRefresher _bookAchievementRefresher;



  // Plan state
  ReadingPlan? _currentPlan;
  UserPlanProgress? _currentPlanProgress;
  ReadingPlanDay? _scheduledDay;

  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    _bookAchievementRefresher = BookAchievementRefresher(
      achievementService: widget.achievementService,
      groupBookAchievementService: widget.groupBookAchievementService,
    );
    _loadInitialData();
    _animationController.forward();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadReadStatus(showLoading: false),
      _loadFriendlyStreak(showLoading: false),
      _loadActivePlan(showLoading: false),
    ]);
    if (!_disposed && mounted) {
      setState(() {
        _initialLoading = false;
      });
    }
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth) {
      unawaited(_loadReadStatus());
      unawaited(_loadFriendlyStreak());
      unawaited(_loadActivePlan());
    }
    if (oldWidget.achievementService != widget.achievementService ||
        oldWidget.groupBookAchievementService !=
            widget.groupBookAchievementService) {
      _bookAchievementRefresher = BookAchievementRefresher(
        achievementService: widget.achievementService,
        groupBookAchievementService: widget.groupBookAchievementService,
      );
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
          _currentStreak = status.streak;
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
          _friendStreaks = null;
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

    final summary = await widget.friendlyStreakService.fetchLinks(uid);
    if (!_disposed && mounted) {
      setState(() {
        _friendStreaks = summary;
        _friendStreakLoading = false;
      });
    }
  }

  Future<void> _loadActivePlan({bool showLoading = true}) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    
    // Listen to the stream for real-time updates
    widget.readingPlanService.getActivePlans(uid).listen((plans) async {
       if (plans.isEmpty) {
         if (!_disposed && mounted) {
           setState(() {
             _currentPlan = null;
             _currentPlanProgress = null;
             _scheduledDay = null;
           });
         }
         return;
       }

       // Just take the first one for now as we don't have multi-plan UI yet
       final progress = plans.first;
       final plan = await widget.readingPlanService.getPlanById(progress.planId);
       
       if (plan != null) {
          final day = widget.readingPlanService.getScheduledDay(plan, progress.startDate, DateTime.now());
          
          if (!_disposed && mounted) {
            setState(() {
              _currentPlan = plan;
              _currentPlanProgress = progress;
              _scheduledDay = day;
            });
          }
       }
    });
  }

  /// Cleans and updates the cached summary document without scanning the entire
  /// reading collection. Removes outdated entries, ensures the summary document
  /// exists and resets the streak if a day was missed.
  Future<bool> _updateSummary({bool showErrorSnackBar = true}) async {
    final user = widget.auth.currentUser;
    if (user == null) return false;

    try {
      final stats = await widget.readingStatusService.updateSummary();
      await _checkAchievements(user.uid, stats.streak, stats.totalReadDays);
      return true;
    } catch (e, st) {
      return _handleRefreshError(
        e,
        st,
        logPrefix: 'Failed to update summary',
        snackBarMessage: 'Failed to update summary. Please try again.',
        showErrorSnackBar: showErrorSnackBar,
        onAfterError: () => unawaited(_loadReadStatus(showLoading: false)),
      );
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
    
    // Also track if we successfully marked the plan day
    bool markedPlanDay = false;

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

      // Mark plan day if relevant
      if (_currentPlan != null && _scheduledDay != null) {
        await widget.readingPlanService.markDayComplete(
            user.uid, _currentPlan!.id, _scheduledDay!.day);
        markedPlanDay = true;
      }

      // Update summary collection (lightweight update)
      final summary = await _updateSummaryWithToday();
      if (summary != null) {
        await widget.friendStreakLinkService.recordCoverage(
          user.uid,
          summary.coveredDate,
          summary.coveredViaGrace,
        );
      }
      await _refreshBookAchievementsForUser();

      // Removed success animation after backend success to reduce noise.

      unawaited(_loadReadStatus(showLoading: false));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to mark reading: $e');
      }
      ErrorLogger.log(e, st);
      
      // Revert plan day if needed (though it's idempotent mostly)
      if (markedPlanDay && _currentPlan != null && _scheduledDay != null) {
         try {
           await widget.readingPlanService.unmarkDayComplete(
               user.uid, _currentPlan!.id, _scheduledDay!.day);
         } catch (_) { /* ignore rollback errors */ }
      }

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
  Future<SummaryStats?> _updateSummaryWithToday() async {
    final user = widget.auth.currentUser;
    if (user == null) return null;

    try {
      final stats = await widget.readingStatusService.updateSummary();
      await _checkAchievements(user.uid, stats.streak, stats.totalReadDays);
      return stats;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to update summary with today: $e');
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
      return null;
    }
  }

  Future<bool> _refreshBookAchievementsForUser({
    bool showErrorSnackBar = true,
  }) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) {
      return false;
    }

    try {
      await _bookAchievementRefresher.refresh(
        uid: uid,
        completionTimestamp: DateTime.now(),
      );
      return true;
    } catch (e, st) {
      return _handleRefreshError(
        e,
        st,
        logPrefix: 'Failed to refresh book achievements',
        snackBarMessage: 'Failed to refresh achievements. Please try again.',
        showErrorSnackBar: showErrorSnackBar,
      );
    }
  }

  bool _handleRefreshError(
    Object error,
    StackTrace stackTrace, {
    required String logPrefix,
    required String snackBarMessage,
    required bool showErrorSnackBar,
    VoidCallback? onAfterError,
  }) {
    if (kDebugMode) {
      debugPrint('$logPrefix: $error');
    }
    ErrorLogger.log(error, stackTrace);
    if (showErrorSnackBar && !_disposed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(snackBarMessage),
        ),
      );
      onAfterError?.call();
    }
    return false;
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

  Future<void> _performRefresh() async {
    try {
      await widget.auth.currentUser?.reload();
      final googleSignIn = widget.googleSignInProvider();
      final googleAccount = await googleSignIn.signInSilently();
      final firebaseUser = widget.auth.currentUser;
      if (googleAccount != null && firebaseUser != null) {
        await firebaseUser.updateDisplayName(googleAccount.displayName);
        await firebaseUser.reload();
      }
      final summarySuccess = await _updateSummary(showErrorSnackBar: false);
      if (!summarySuccess) {
        throw Exception('Summary refresh failed');
      }

      final achievementsSuccess = await _refreshBookAchievementsForUser(
        showErrorSnackBar: false,
      );
      if (!achievementsSuccess) {
        throw Exception('Book achievements refresh failed');
      }
      await _loadReadStatus();
      await _loadFriendlyStreak(showLoading: false);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Refresh failed: $e');
      }
      ErrorLogger.log(e, st);
      rethrow;
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
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        forceMaterialTransparency: true,
        backgroundColor: Colors.transparent,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark, // Android: Dark icons
          statusBarBrightness: Brightness.light,    // iOS: Dark icons
        ),
      ),
      body: SkeletonLoader(
        loading: _initialLoading,
        skeleton: const HomePageSkeleton(),
        child: _buildMinimalContent(context),
      ),
    );
  }

  /// Groups sequential chapters (e.g., "Genesis 1", "Genesis 2" -> "Genesis 1–2").
  String _formatReadings(List<String> readings) {
    if (readings.isEmpty) return '';

    final List<String> result = [];
    String? currentBook;
    List<int> currentChapters = [];

    void flush() {
      if (currentBook == null) return;
      if (currentChapters.isEmpty) return;

      // Format chapters
      List<String> ranges = [];
      currentChapters.sort(); // Ensure sorted, though input usually is
      int start = currentChapters[0];
      int end = start;

      for (int i = 1; i < currentChapters.length; i++) {
        if (currentChapters[i] == end + 1) {
          end = currentChapters[i];
        } else {
          ranges.add(start == end ? '$start' : '$start–$end');
          start = currentChapters[i];
          end = currentChapters[i];
        }
      }
      ranges.add(start == end ? '$start' : '$start–$end');
      result.add('$currentBook ${ranges.join(", ")}');
    }

    for (var reading in readings) {
      final match = RegExp(r'^(.+)\s+(\d+)$').firstMatch(reading);
      if (match != null) {
        final book = match.group(1)!;
        final chapter = int.parse(match.group(2)!);

        if (book != currentBook) {
          flush();
          currentBook = book;
          currentChapters = [chapter];
        } else {
          currentChapters.add(chapter);
        }
      } else {
        flush();
        currentBook = null;
        currentChapters = [];
        result.add(reading);
      }
    }
    flush();
    return result.join(', ');
  }

  Widget _buildMinimalContent(BuildContext context) {
    if (widget.auth.currentUser == null) {
      return Center(
        child: Text(
          'User not signed in.',
          style: AppTextStyles.subtitle.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    // Minimal UI: Centered content, no distractions.
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 3),
            if (_readToday) ...[
              Icon(
                Icons.check_circle_outline_rounded,
                size: 80,
                color: colorScheme.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 24),
              Text(
                'Thank you for being here.',
                style: AppTextStyles.subtitle.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface.withValues(alpha: 0.9),
                  letterSpacing: 0.0,
                ),
                textAlign: TextAlign.center,
              ),
            ] else ...[
              if (_scheduledDay != null) ...[
                Text(
                  'TODAY\'S READING',
                  style: AppTextStyles.caption.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  _formatReadings(_scheduledDay!.readings),
                  style: AppTextStyles.title.copyWith(
                    fontSize: 26,
                    fontWeight: FontWeight.w400,
                    height: 1.3,
                    color: colorScheme.onSurface.withValues(alpha: 0.9),
                    fontFamily: 'Serif',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 56),
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton(
                    onPressed: _toggleLoading ? null : _toggleReadStatus,
                    child: _toggleLoading
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : Text(
                            'I have read',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                  ),
                ),
              ] else ...[
                Text(
                  'Daily Reading',
                  style: AppTextStyles.caption.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Did you read today?',
                  style: AppTextStyles.title.copyWith(
                    fontSize: 26,
                    fontWeight: FontWeight.w400,
                    color: colorScheme.onSurface.withValues(alpha: 0.9),
                    fontFamily: 'Serif',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton.tonal(
                    onPressed: _toggleLoading ? null : _toggleReadStatus,
                    style: FilledButton.styleFrom(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                    child: _toggleLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text('Yes, I read'),
                  ),
                ),
              ],
            ],

            const Spacer(flex: 4), // Push progress lower

            // Weekly Progress Section - Visual separation
            if (_readToday) ...[
              // Weekly Progress Section
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reading this week',
                        style: AppTextStyles.body.copyWith(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colorScheme.outline.withValues(alpha: 0.1),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _pastWeek.isEmpty 
                                ? 0.0 
                                : _pastWeek.where((d) => d).length / 7.0,
                            minHeight: 10,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              colorScheme.primary.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Streak Count
              if (_currentStreak > 0)
                RichText(
                   text: TextSpan(
                     style: AppTextStyles.body.copyWith(
                       fontSize: 13,
                       color: colorScheme.outline,
                     ),
                     children: [
                       TextSpan(
                         text: '$_currentStreak',
                         style: const TextStyle(fontWeight: FontWeight.w600),
                       ),
                       TextSpan(text: ' days of reading'),
                     ],
                   ),
                ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _animationController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;
}
