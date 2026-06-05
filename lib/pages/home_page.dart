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
import '../services/catch_up_engine.dart';
import '../services/plan_completion_coordinator.dart';
import '../services/reading_plan_service.dart';
import '../services/reading_status_service.dart';
import '../services/user_preferences_service.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';

import '../services/vibration_service.dart';
import '../widgets/catch_up_status_row.dart';
import '../widgets/common_styles.dart'; // Kept for AppTextStyles if used, or verify usage. Check minimal usage.
import '../widgets/skeleton_loader.dart';
import '../widgets/skeletons/home_page_skeleton.dart';
import '../widgets/app_header.dart';
import 'plan_detail_page.dart';
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
              auth: auth ?? FirebaseAuth.instance,
            ),
        readingPlanService = readingPlanService ??
            ReadingPlanService(
              firestore: firestore ?? FirebaseFirestore.instance,
            ),
        userPreferencesService = userPreferencesService ??
            UserPreferencesService(
              firestore: firestore ?? FirebaseFirestore.instance,
            ),
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
  bool _isSyncing = false;
  List<bool> _pastWeek = [];
  List<bool> _pastMonth = [];
  Set<DateTime> _readDates = {};
  int _currentStreak = 0;
  int _totalReadDays = 0;

  // Plan state. The active personal plan, its progress, and today's scheduled
  // reading are retained so Home can render the secondary "Today's reading"
  // card with its own mark + catch-up affordance (epic #716, issues #722/#723).
  StreamSubscription<DocumentSnapshot>? _syncSub;

  ReadingPlanDay? _scheduledDay;
  ReadingPlan? _activePlan;
  UserPlanProgress? _activeProgress;

  /// Whether the plan-reading card's mark is mid-write.
  bool _planToggleLoading = false;

  late final PlanCompletionCoordinator _completionCoordinator;

  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _completionCoordinator = PlanCompletionCoordinator(
      firestore: widget.firestore,
      planService: widget.readingPlanService,
    );
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _loadInitialData();
    _setupSyncListener();
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
    ];

    await Future.wait(futures);
  }

  void _setupSyncListener() {
    _syncSub?.cancel();
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isSyncing = false);
      return;
    }

    _syncSub = widget.firestore
        .collection('users')
        .doc(uid)
        .snapshots(includeMetadataChanges: true)
        .listen(
      (snapshot) {
        final hasPendingWrites = snapshot.metadata.hasPendingWrites;
        if (!_disposed && mounted && _isSyncing != hasPendingWrites) {
          setState(() {
            _isSyncing = hasPendingWrites;
          });
        }
      },
      onError: (e, st) {
        if (kDebugMode) {
          debugPrint('Error in sync listener: $e');
        }
        ErrorLogger.log(e, st);
      },
    );
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth) {
      setState(() {
        _initialLoading = true;
      });
      _setupSyncListener();
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

  Future<void> _loadActivePlan({bool showLoading = true}) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;

    final completer = Completer<void>();
    bool firstEvent = true;

    // Listen to the stream for real-time updates
    widget.readingPlanService.getActivePlans(uid).listen(
      (plans) async {
        if (plans.isEmpty) {
          if (!_disposed && mounted) {
            setState(() {
              _scheduledDay = null;
              _activePlan = null;
              _activeProgress = null;
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
        final plan = await widget.readingPlanService.getPlanById(
          progress.planId,
          userId: uid,
        );

        if (plan != null) {
          final day = widget.readingPlanService.getScheduledDay(
            plan,
            progress.startDate,
            widget.dateProvider(),
          );

          if (!_disposed && mounted) {
            setState(() {
              _scheduledDay = day;
              _activePlan = plan;
              _activeProgress = progress;
            });
          }
        }

        if (firstEvent) {
          firstEvent = false;
          completer.complete();
        }
      },
      onError: (e) {
        if (firstEvent) {
          firstEvent = false;
          completer.completeError(e);
        }
      },
    );

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

    try {
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      // The daily habit is a pure presence mark — it never advances any plan.
      // Coupling is one-directional: finishing a plan reading may optionally
      // record the habit (see PlanDetailPage), but the bare habit tap does not
      // touch plan progress.
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
            .set({'read': true}, SetOptions(merge: true)),
      ];

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

  /// Marks (or un-marks) today's scheduled *plan* reading. Distinct from the
  /// bare habit tap: this advances the personal plan, and — when the user has
  /// opted in — may also record the daily habit via [PlanCompletionCoordinator]
  /// (one-directional reading→habit coupling). Un-marking never touches the
  /// habit.
  Future<void> _togglePlanReading() async {
    final user = widget.auth.currentUser;
    final plan = _activePlan;
    final progress = _activeProgress;
    final day = _scheduledDay?.day;
    if (user == null || plan == null || progress == null || day == null) return;
    if (_planToggleLoading) return;

    unawaited(widget.vibrationService.lightImpact());

    final wasCompleted = progress.completedDays.contains(day);
    final previousProgress = progress;

    // Optimistically reflect the new completion set locally.
    final newDays = List<int>.from(progress.completedDays);
    if (wasCompleted) {
      newDays.remove(day);
    } else if (!newDays.contains(day)) {
      newDays.add(day);
    }
    if (!_disposed && mounted) {
      setState(() {
        _planToggleLoading = true;
        _activeProgress = progress.copyWith(completedDays: newDays);
      });
    }

    try {
      if (wasCompleted) {
        await widget.readingPlanService.unmarkDayComplete(
          user.uid,
          plan.id,
          day,
        );
      } else {
        if (!mounted) return;
        await _completionCoordinator.completePlanDay(
          context: context,
          user: user,
          planId: plan.id,
          day: day,
        );
        // The coupling may have recorded the habit; refresh habit state.
        widget.readingStatusService.invalidateCache();
        unawaited(_loadReadStatus(showLoading: false));
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to update plan reading: $e');
      }
      ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        setState(() {
          _activeProgress = previousProgress;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update reading. Please try again.'),
          ),
        );
      }
    } finally {
      if (!_disposed && mounted) {
        setState(() {
          _planToggleLoading = false;
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
                loading: _initialLoading || _isSyncing,
                minTime: const Duration(milliseconds: 1000),
                skeleton: const HomePageSkeleton(),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // SliverToBoxAdapter (not SliverFillRemaining) so the
                    // habit-first column takes its natural height and scrolls
                    // when it exceeds the viewport, rather than overflowing.
                    SliverToBoxAdapter(
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
              child: AppHeader(
                auth: widget.auth,
                firestore: widget.firestore,
                vibrationService: widget.vibrationService,
                dateProvider: widget.dateProvider,
                showProfileIcon: false,
                showNotificationBell: false,
                showGreeting: false,
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
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    final hasPlan = _activePlan != null && _scheduledDay != null;

    // Home is "the act": the daily habit is the hero, with an optional, clearly
    // secondary "Today's reading" plan card below it (epic #716, #722/#723).
    // The long-arc plan progress (meter, Day x/y, schedule) lives on Journey.
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        // Content is top-aligned (habit hero first) and laid out at its natural
        // height; the enclosing CustomScrollView scrolls it when tall.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Clear the overlaid AppHeader.
            const SizedBox(height: 76),
            _buildHabitHero(context, hasPlan: hasPlan),
            if (hasPlan) ...[
              const SizedBox(height: 28),
              _buildTodaysReadingSection(context),
            ],
            if (_readToday) ...[
              const SizedBox(height: 40),
              _buildHabitStats(context),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// The daily habit — the heartbeat of Home. Visually dominant; one tap; never
  /// gated by, and never advancing, any plan.
  Widget _buildHabitHero(BuildContext context, {required bool hasPlan}) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: _readToday
          ? Container(
              key: const ValueKey('habit_done'),
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 72,
                    color: colorScheme.primary.withValues(alpha: 0.85),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Thank you for being here',
                    style: AppTextStyles.subtitle(context).copyWith(
                      fontSize: 24,
                      color: colorScheme.onSurface.withValues(alpha: 0.9),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : Container(
              key: const ValueKey('habit_todo'),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'THE PRACTICE',
                    style: AppTextStyles.caption(context).copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    hasPlan
                        ? 'Did you spend time in the Word?'
                        : 'Read whatever you’re drawn to.',
                    style: AppTextStyles.title(context).copyWith(
                      fontSize: 26,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                      color: colorScheme.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'However much you read, showing up is the whole thing.',
                    style: AppTextStyles.bodySmall(context).copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: Semantics(
                      button: true,
                      label: 'Mark daily reading as complete',
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
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_rounded, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'I read today',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onPrimary,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      hasPlan
                          ? 'Counts whether or not you followed your plan.'
                          : 'Open your Bible — mark it here when you’re done.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption(context).copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// The secondary "Today's reading" card: the personal plan's scheduled
  /// chapter with its own mark, plus a gentle catch-up row. Shown only when an
  /// active plan exists (#723 — no plan ⇒ nothing prescriptive here).
  Widget _buildTodaysReadingSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final day = _scheduledDay!;
    final isRead = _activeProgress!.completedDays.contains(day.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Today’s reading',
          style: theme.textTheme.titleSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.explore_outlined,
                      size: 14, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _activePlan!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _formatReadings(day.readings),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: isRead
                    ? OutlinedButton.icon(
                        onPressed:
                            _planToggleLoading ? null : _togglePlanReading,
                        icon: Icon(Icons.check_circle,
                            size: 20, color: colorScheme.primary),
                        label: const Text('Read'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.primary,
                          side: BorderSide(
                            color: colorScheme.primary.withValues(alpha: 0.4),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      )
                    : FilledButton.tonalIcon(
                        onPressed:
                            _planToggleLoading ? null : _togglePlanReading,
                        icon: _planToggleLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 20),
                        label: const Text('Mark as read'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Reuse the shared catch-up row (#720) so Home, Journey and Community
        // present the engine-computed behind/on-track state identically.
        CatchUpStatusRow(
          status: CatchUpEngine.forPersonalPlan(
            _activePlan!,
            _activeProgress!,
            today: widget.dateProvider(),
          ),
          onTap: _openPlanSchedule,
        ),
      ],
    );
  }

  void _openPlanSchedule() {
    final plan = _activePlan;
    final progress = _activeProgress;
    if (plan == null) return;
    unawaited(widget.vibrationService.lightImpact());
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlanDetailPage(
          plan: plan,
          firestore: widget.firestore,
          auth: widget.auth,
          initialProgress: progress,
          vibrationService: widget.vibrationService,
        ),
      ),
    );
  }

  /// Habit stats — the lightweight "showing up" record (weekly bar + streak).
  /// These describe the *habit*, not plan progress, so they stay on Home.
  Widget _buildHabitStats(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reading this week',
                style: AppTextStyles.bodySmall(context).copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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
        const SizedBox(height: 24),
        RichText(
          text: TextSpan(
            style: AppTextStyles.bodySmall(context)
                .copyWith(color: colorScheme.outline),
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
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _animationController.dispose();
    _syncSub?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;
}
