import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/error_logger.dart';
import '../services/google_sign_in_factory.dart';
import '../services/bible_progress_service.dart';
import '../services/reading_plan_service.dart';
import '../services/reading_status_service.dart';
import '../services/user_preferences_service.dart';
import '../models/reading_plan.dart';
import '../models/user_preferences.dart';

import '../services/vibration_service.dart';
import '../widgets/common_styles.dart'; // Kept for AppTextStyles if used, or verify usage. Check minimal usage.
import '../widgets/skeleton_loader.dart';
import '../widgets/skeletons/home_page_skeleton.dart';
import '../widgets/app_header.dart';
import '../widgets/syncing_indicator.dart';
import 'read_log_page.dart';

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
    required this.dateProvider,
    ReadingStatusService? readingStatusService,
    VibrationService? vibrationService,
    GoogleSignIn Function()? googleSignInProvider,
    BibleProgressService? bibleProgressService,
    ReadingPlanService? readingPlanService,
    UserPreferencesService? userPreferencesService,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        readingStatusService = readingStatusService ??
            ReadingStatusService(
                firestore: firestore ?? FirebaseFirestore.instance,
                auth: auth ?? FirebaseAuth.instance),
        readingPlanService = readingPlanService ??
            ReadingPlanService(
                firestore: firestore ?? FirebaseFirestore.instance),
        userPreferencesService = userPreferencesService ??
            UserPreferencesService(
                firestore: firestore ?? FirebaseFirestore.instance),
        vibrationService = vibrationService ?? const VibrationService(),
        googleSignInProvider = googleSignInProvider ?? createGoogleSignIn,
        bibleProgressService =
            bibleProgressService ?? BibleProgressService(firestore: firestore);

  /// Service for loading and updating reading status.
  final ReadingStatusService readingStatusService;

  /// Service used for read-toggle haptics.
  final VibrationService vibrationService;

  /// Aggregates reading progress across groups for book badges.
  final BibleProgressService bibleProgressService;

  /// Service for managing reading plans.
  final ReadingPlanService readingPlanService;

  /// Service for managing user preferences.
  final UserPreferencesService userPreferencesService;

  final DateTime Function() dateProvider;

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
  bool _prefsLoaded = false;
  List<bool> _pastWeek = [];
  List<bool> _pastMonth = [];
  Set<DateTime> _readDates = {};
  int _currentStreak = 0;
  int _totalReadDays = 0;

  // Plan state
  ReadingPlan? _currentPlan;
  UserPreferences _userPrefs = const UserPreferences();
  StreamSubscription<UserPreferences>? _prefSub;

  ReadingPlanDay? _scheduledDay;

  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    _loadInitialData();
    _animationController.forward();
  }

  Future<void> _loadInitialData() async {
    // Start all loads in parallel.
    // _initialLoading will be set to false when the primary reading status is ready.
    final futures = [
      _loadReadStatus(showLoading: false).then((_) {
        if (!_disposed && mounted) {
          setState(() {
            _initialLoading = false;
          });
        }
      }),
      _loadActivePlan(showLoading: false),
      _loadUserPreferences().then((_) {
        if (!_disposed && mounted) {
          setState(() {
            _prefsLoaded = true;
          });
        }
      }),
    ];

    await Future.wait(futures);
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth) {
      setState(() {
        _initialLoading = true;
        _prefsLoaded = false;
      });
      unawaited(_loadInitialData());
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
          _currentStreak = status.streak;
          _totalReadDays = status.totalReadDays;
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

  Future<void> _loadUserPreferences() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;

    final completer = Completer<void>();
    bool firstEvent = true;

    _prefSub?.cancel();
    _prefSub = widget.userPreferencesService.streamPreferences(uid).listen(
      (prefs) {
        if (!_disposed && mounted) {
          setState(() {
            _userPrefs = prefs;
          });
        }
        if (firstEvent) {
          firstEvent = false;
          completer.complete();
        }
      },
      onError: (e, st) {
        if (kDebugMode) {
          debugPrint('Error loading preferences: $e');
        }
        ErrorLogger.log(e, st);
        if (firstEvent) {
          firstEvent = false;
          completer.complete(); // Still complete to avoid hanging
        }
      },
    );

    return completer.future;
  }

  Future<void> _loadActivePlan({bool showLoading = true}) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;

    final completer = Completer<void>();
    bool firstEvent = true;

    // Listen to the stream for real-time updates
    widget.readingPlanService.getActivePlans(uid).listen((plans) async {
      if (plans.isEmpty) {
        if (!_disposed && mounted) {
          setState(() {
            _currentPlan = null;

            _scheduledDay = null;
          });
        }
        if (firstEvent) {
          firstEvent = false;
          completer.complete();
        }
        return;
      }

      // Just take the first one for now as we don't have multi-plan UI yet
      final progress = plans.first;
      final plan = await widget.readingPlanService
          .getPlanById(progress.planId, userId: uid);

      if (plan != null) {
        final day = widget.readingPlanService
            .getScheduledDay(plan, progress.startDate, widget.dateProvider());

        if (!_disposed && mounted) {
          setState(() {
            _currentPlan = plan;
            _scheduledDay = day;
          });
        }
      }

      if (firstEvent) {
        firstEvent = false;
        completer.complete();
      }
    }, onError: (e) {
      if (firstEvent) {
        firstEvent = false;
        completer.completeError(e);
      }
    });

    return completer.future;
  }

  /// Marks the current day as read. Optimistically updates local state and
  /// writes the change to Firestore, rolling back on failure.
  Future<void> _toggleReadStatus() async {
    unawaited(widget.vibrationService.mediumImpact());
    if (_readToday) return;

    final user = widget.auth.currentUser;
    if (user == null) return;

    // Preserve current state in case we need to revert on error.
    final prevWeek = List<bool>.from(_pastWeek);
    final prevMonth = List<bool>.from(_pastMonth);
    final prevReadDates = Set<DateTime>.from(_readDates);
    final prevStreak = _currentStreak;
    final prevTotalReadDays = _totalReadDays;

    final today = widget.dateProvider();
    final weekIndex = today.weekday % 7;
    final monthIndex = today.day - 1;
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;

    if (!_disposed && mounted) {
      setState(() {
        _toggleLoading = true;
        // Optimistically mark today as read in local state.
        _readToday = true;
        _currentStreak += 1; // Increment streak optimistically.
        _totalReadDays += 1; // Increment total days optimistically.

        if (_pastWeek.length < 7) {
          _pastWeek = List<bool>.generate(
            7,
            (i) => i < _pastWeek.length ? _pastWeek[i] : false,
          );
        } else {
          // Create a new list to ensure the UI updates correctly.
          _pastWeek = List<bool>.from(_pastWeek);
        }
        _pastWeek[weekIndex] = true;

        if (_pastMonth.length < daysInMonth) {
          _pastMonth = List<bool>.generate(
            daysInMonth,
            (i) => i < _pastMonth.length ? _pastMonth[i] : false,
          );
        } else {
          // Create a new list to ensure the UI updates correctly.
          _pastMonth = List<bool>.from(_pastMonth);
        }
        _pastMonth[monthIndex] = true;
        _readDates.add(DateTime(today.year, today.month, today.day));
      });
    }

    // Reload user before writing to Firestore.
    try {
      await user.reload();
    } catch (_) {}
    final refreshedUser = widget.auth.currentUser;

    // Also track if we successfully marked the plan day
    bool markedPlanDay = false;

    try {
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      // Determine if we should mark the plan day.
      // We do this immediately (optimistically) before waiting for daily reading writes.
      bool markPlan = false;
      if (_currentPlan != null && _scheduledDay != null) {
        if (_prefsLoaded) {
          markPlan = _userPrefs.autoMarkPlanRead;
        }
      }

      final List<Future<void>> backendWrites = [
        ReadLogPage.writeReadLogEntry(
          refreshedUser ?? user,
          firestore: widget.firestore,
          functions: widget.functions,
          markFirstReader: widget.markFirstReader,
          dateProvider: () => today,
        ),
        widget.firestore
            .collection('users')
            .doc(user.uid)
            .collection('reading')
            .doc(dateKey)
            .set({
          'read': true,
        }, SetOptions(merge: true)),
      ];

      // Mark plan day if relevant
      if (markPlan && _currentPlan != null && _scheduledDay != null) {
        backendWrites.add(widget.readingPlanService
            .markDayComplete(user.uid, _currentPlan!.id, _scheduledDay!.day));
        markedPlanDay = true;
      }

      // Execute all backend writes in parallel
      await Future.wait(backendWrites);

      // Update summary collection (lightweight update)
      await _updateSummaryWithToday();

      // Removed success animation after backend success to reduce noise.

      // Invalidate cache so the next tab visit fetches fresh data.
      widget.readingStatusService.invalidateCache();
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
        } catch (_) {/* ignore rollback errors */}
      }

      if (!_disposed && mounted) {
        // Revert to previous state and notify the user.
        setState(() {
          _readToday = false;
          _pastWeek = prevWeek;
          _pastMonth = prevMonth;
          _readDates = prevReadDates;
          _currentStreak = prevStreak;
          _totalReadDays = prevTotalReadDays;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to mark reading. Please try again.'),
          ),
        );
      }
    } finally {
      if (!_disposed && mounted) {
        setState(() {
          _toggleLoading = false;
        });
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

  /// Adds a like entry for today's reading document.
  Future<void> likeReading() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    final today = widget.dateProvider();
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

    final today = widget.dateProvider();
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
      body: Stack(
        children: [
          // Background/Main Content
          Positioned.fill(
            child: RefreshIndicator(
              onRefresh: _loadInitialData,
              child: SkeletonLoader(
                loading: _initialLoading,
                minTime: const Duration(milliseconds: 1000),
                skeleton: const HomePageSkeleton(),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildMinimalContent(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // AppHeader overlaid at top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  AppHeader(
                    auth: widget.auth,
                    firestore: widget.firestore,
                    vibrationService: widget.vibrationService,
                    dateProvider: widget.dateProvider,
                    showProfileIcon: false,
                    showNotificationBell: false,
                    showGreeting: false,
                  ),
                  if (widget.auth.currentUser != null)
                    SyncingIndicator(
                      firestore: widget.firestore,
                      userId: widget.auth.currentUser!.uid,
                    ),
                ],
              ),
            ),
          ),
        ],
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
          style: AppTextStyles.subtitle(context).copyWith(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    // Minimal UI: Core content centered, progress at bottom.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Stack(
        children: [
          // Centered main content: Reading info or "Thank you"
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _readToday
                  ? Column(
                      key: const ValueKey('read_state'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          size: 80,
                          color: colorScheme.primary.withValues(alpha: 0.8),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Thank you for being here.',
                          style: AppTextStyles.subtitle(context).copyWith(
                            fontSize: 24,
                            color: colorScheme.onSurface.withValues(alpha: 0.9),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    )
                  : Column(
                      key: const ValueKey('unread_state'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_scheduledDay != null) ...[
                          Text(
                            'TODAY\'S READING',
                            style: AppTextStyles.caption(context).copyWith(
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            _formatReadings(_scheduledDay!.readings),
                            style: AppTextStyles.title(context).copyWith(
                              fontSize: 26,
                              fontWeight: FontWeight.w400,
                              height: 1.3,
                              color:
                                  colorScheme.onSurface.withValues(alpha: 0.9),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 56),
                          SizedBox(
                            width: double.infinity,
                            height: 64,
                            child: Semantics(
                              button: true,
                              label: "Mark today's reading as complete",
                              child: Tooltip(
                                message: 'Mark as read',
                                child: FilledButton(
                                  onPressed:
                                      _toggleLoading ? null : _toggleReadStatus,
                                  child: _toggleLoading
                                      ? SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: colorScheme.onPrimary,
                                          ),
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'I have read',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black,
                                                  ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          Text(
                            'Daily Reading',
                            style: AppTextStyles.caption(context).copyWith(
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'How did your reading go today?',
                            style: AppTextStyles.title(context).copyWith(
                              fontSize: 26,
                              fontWeight: FontWeight.w400,
                              color:
                                  colorScheme.onSurface.withValues(alpha: 0.9),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 48),
                          SizedBox(
                            width: double.infinity,
                            height: 64,
                            child: Semantics(
                              button: true,
                              label: 'Mark daily reading as complete',
                              child: Tooltip(
                                message: 'Mark as read',
                                child: FilledButton.tonal(
                                  onPressed:
                                      _toggleLoading ? null : _toggleReadStatus,
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
                                      : const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text('Yes, I read'),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
          // Bottom section: Progress (only if readToday)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 800),
            child: _readToday
                ? Align(
                    key: const ValueKey('bottom_progress'),
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Weekly Progress Section
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 240),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Reading this week',
                                  style: AppTextStyles.bodySmall(context)
                                      .copyWith(
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest
                                        .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: colorScheme.outline
                                          .withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: _pastWeek.isEmpty
                                          ? 0.0
                                          : _pastWeek.where((d) => d).length /
                                              7.0,
                                      minHeight: 10,
                                      backgroundColor: Colors.transparent,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        colorScheme.primary
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          RichText(
                            text: TextSpan(
                              style: AppTextStyles.bodySmall(context).copyWith(
                                color: colorScheme.outline,
                              ),
                              children: [
                                TextSpan(
                                  text: '$_currentStreak',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                const TextSpan(text: ' day streak'),
                                const TextSpan(text: '  •  '),
                                TextSpan(
                                  text: '$_totalReadDays',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const TextSpan(text: ' days total'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('bottom_empty')),
          ),
        ],
      ),
    );
  }


  @override
  void dispose() {
    _disposed = true;
    _animationController.dispose();
    _prefSub?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;
}
