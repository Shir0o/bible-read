import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/error_logger.dart';
import '../services/google_sign_in_factory.dart';
import '../services/active_reading_aggregator.dart';
import '../services/bible_progress_service.dart';
import '../services/catch_up_engine.dart' hide ReadingStatus;
import '../services/circle_service.dart';
import '../services/group_service.dart';
import '../services/habit_lifecycle_service.dart';
import '../services/reading_plan_service.dart';
import '../services/reading_status_service.dart';
import '../services/reflection_service.dart';
import '../services/user_preferences_service.dart';
import '../models/group_member_progress.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';
import '../models/reflection.dart';

import '../services/vibration_service.dart';
import '../widgets/burst_undo_controller.dart';
import '../widgets/catch_up_status_row.dart';
import '../widgets/common_styles.dart'; // Kept for AppTextStyles if used, or verify usage. Check minimal usage.
import '../theme/app_theme.dart';
import '../widgets/member_presence_stack.dart';
import '../services/read_log_service.dart';

import '../widgets/app_header.dart';
import '../widgets/sun_mark.dart';
import '../widgets/reflect_sheet.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/skeletons/home_page_skeleton.dart';
import 'adjust_pace_page.dart';
import 'check_in_page.dart';
import 'plan_detail_page.dart';

/// Landing page that displays reading progress and loads user data from
/// Firestore when the app starts.
class HomePage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final GoogleSignIn Function() googleSignInProvider;

  HomePage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    required this.dateProvider,
    this.onOpenJourney,
    this.onOpenCommunity,
    ReadingStatusService? readingStatusService,
    VibrationService? vibrationService,
    GoogleSignIn Function()? googleSignInProvider,
    BibleProgressService? bibleProgressService,
    ReadingPlanService? readingPlanService,
    UserPreferencesService? userPreferencesService,
    ReflectionService? reflectionService,
    GroupService? groupService,
    CircleService? circleService,
    ActiveReadingAggregator? activeReadingAggregator,
    this.habitLifecycleService,
    this.enableDriftAnimation = true,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        readingStatusService = readingStatusService ??
            ReadingStatusService(
              firestore: firestore ?? FirebaseFirestore.instance,
              auth: auth ?? FirebaseAuth.instance,
              dateProvider: dateProvider,
            ),
        readingPlanService = readingPlanService ??
            ReadingPlanService(
              firestore: firestore ?? FirebaseFirestore.instance,
            ),
        userPreferencesService = userPreferencesService ??
            UserPreferencesService(
              firestore: firestore ?? FirebaseFirestore.instance,
            ),
        reflectionService = reflectionService ??
            ReflectionService(
              firestore: firestore ?? FirebaseFirestore.instance,
            ),
        vibrationService = vibrationService ?? const VibrationService(),
        googleSignInProvider = googleSignInProvider ?? createGoogleSignIn,
        bibleProgressService =
            bibleProgressService ?? BibleProgressService(firestore: firestore),
        groupService = groupService ??
            GroupService(firestore: firestore ?? FirebaseFirestore.instance),
        circleService = circleService ??
            (groupService?.circleService ??
                CircleService(
                  firestore: firestore ?? FirebaseFirestore.instance,
                )),
        activeReadingAggregator = activeReadingAggregator ??
            ActiveReadingAggregator(
              firestore: firestore ?? FirebaseFirestore.instance,
              readingPlanService: readingPlanService ??
                  ReadingPlanService(
                    firestore: firestore ?? FirebaseFirestore.instance,
                  ),
              groupService: groupService ??
                  GroupService(
                    firestore: firestore ?? FirebaseFirestore.instance,
                  ),
              userPreferencesService: userPreferencesService ??
                  UserPreferencesService(
                    firestore: firestore ?? FirebaseFirestore.instance,
                  ),
              dateProvider: dateProvider,
            );

  /// Deep module aggregating active personal and shared reading items.
  final ActiveReadingAggregator activeReadingAggregator;

  /// Service managing the showing-up daily habit lifecycle.
  final HabitLifecycleService? habitLifecycleService;

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

  /// Service for loading and saving the day's private reflection.
  final ReflectionService reflectionService;

  /// Loads the user's group, its schedule and member presence for the
  /// "together" reading card (design parity — Home shared-plan section).
  final GroupService groupService;

  /// Service managing Circle derivation across shared groups.
  final CircleService circleService;

  /// Switches to the Journey tab when the consistency glimpse is tapped.
  final VoidCallback? onOpenJourney;

  /// Switches to the Community tab when the community glimpse is tapped.
  final VoidCallback? onOpenCommunity;

  final DateTime Function() dateProvider;

  final bool enableDriftAnimation;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  bool _disposed = false;
  bool _readToday = false;

  /// Today's saved reflection text, or `null` if none has been saved yet.
  String? _reflection;

  /// Whether today's reflection is currently shared with the Circle (#807).
  bool _reflectionShared = false;

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

  StreamSubscription<DocumentSnapshot>? _syncSub;

  /// Streams the current reading status, so a Firestore change updates Home
  /// without a pull-to-refresh.
  StreamSubscription<ReadingStatus>? _statusSub;

  /// Streams today's reflection document.
  StreamSubscription<dynamic>? _reflectionSub;

  /// Streaming change trigger for today's Circle feed.
  StreamSubscription<dynamic>? _communityFeedSub;

  Timer? _communityRefreshTimer;

  /// Subscription to the active readings aggregator stream.
  StreamSubscription<ActiveReadingsSnapshot>? _readingsSub;

  /// Current snapshot of resolved active readings (plans and groups).
  ActiveReadingsSnapshot _readingsSnapshot = ActiveReadingsSnapshot.empty;

  /// Set of group IDs currently toggling reading status.
  final Set<String> _groupMarkingIds = {};

  /// Tracks whether the CheckInPage was auto-opened on app launch.
  bool _hasAutoOpenedCheckIn = false;

  /// Whether the primary plan card's mark is mid-write.
  bool _planToggleLoading = false;

  // Community presence. The bottom "Your community" glimpse — who among the
  // reader's Circle (the co-members of their Groups) has read today.
  List<_CommunityReader> _communityReaders = [];
  int _communityTotal = 0;

  /// The reading the user pinned as "Primary on Home" (typed key
  /// `plan:<id>` / `group:<id>`), or `null` to let ranking auto-pick the hero.
  /// Set from the All Plans hub; honored in [_buildReadingItems].
  String? _pinnedReadingId;

  /// Whether finishing a plan reading also records the daily habit (Settings'
  /// "Reading counts as showing up" toggle). Drives the "Also counts as
  /// showing up today" hint on not-yet-read mark buttons; the actual coupling
  /// write is owned by [HabitLifecycleService], untouched here.
  bool _autoMarkPlanRead = false;

  late final HabitLifecycleService _habitService;

  /// Coalesces rapid marks into one undoable burst (ADR-0005).
  late final BurstUndoController _burstUndo;

  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _habitService = widget.habitLifecycleService ??
        HabitLifecycleService(
          firestore: widget.firestore,
          planService: widget.readingPlanService,
          readingStatusService: widget.readingStatusService,
        );
    _burstUndo = BurstUndoController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _loadInitialData();
    _setupSyncListener();
    _watchLiveData();
    _animationController.forward();
  }

  /// Starts live listeners for the data Home displays. Firestore snapshots
  /// mean a remote change reaches the tab without a manual refresh, while a
  /// stream that does not change stays quiet.
  void _watchLiveData() {
    _statusSub?.cancel();
    _reflectionSub?.cancel();
    _readingsSub?.cancel();
    _communityFeedSub?.cancel();

    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;

    _statusSub = widget.readingStatusService.watchStatus().listen(
          _applyStatus,
          onError: (Object e, StackTrace st) => ErrorLogger.log(e, st),
        );

    _reflectionSub = widget.reflectionService
        .watchReflection(uid, _dateKeyFor(widget.dateProvider()))
        .listen(
          _applyReflection,
          onError: (Object e, StackTrace st) => ErrorLogger.log(e, st),
        );

    _readingsSub = widget.activeReadingAggregator
        .watch(
      uid,
      dateProvider: widget.dateProvider,
      pinnedReadingId: _pinnedReadingId,
    )
        .listen(
      (snapshot) {
        if (_disposed || mounted == false) return;
        setState(() {
          _readingsSnapshot = snapshot;
        });
      },
      onError: (Object e, StackTrace st) => ErrorLogger.log(e, st),
    );

    _watchCommunity(uid);
  }

  void _applyStatus(ReadingStatus status) {
    if (_disposed || mounted == false) return;
    setState(() {
      _readToday = status.readToday;
      _pastWeek = status.pastWeek;
      _pastMonth = status.pastMonth;
      _readDates = status.readDates;
      _currentStreak = status.streak;
      _totalReadDays = status.totalReadDays;
      _initialLoading = false;
    });
  }

  void _applyReflection(Reflection? reflection) {
    if (_disposed || mounted == false) return;
    setState(() {
      _reflection = reflection?.text;
      _reflectionShared = reflection?.shared ?? false;
    });
  }

  void _watchCommunity(String uid) {
    _communityFeedSub?.cancel();
    final dateKey = _dateKeyFor(widget.dateProvider());
    _communityFeedSub = ReadLogService(firestore: widget.firestore)
        .entryDocsForGroupsForUser(uid, dateKey: dateKey)
        .listen(
          (_) => _scheduleCommunityReload(),
          onError: (Object e, StackTrace st) => ErrorLogger.log(e, st),
        );
  }

  void _scheduleCommunityReload() {
    _communityRefreshTimer?.cancel();
    _communityRefreshTimer = Timer(
      const Duration(milliseconds: 250),
      () {
        if (_disposed || mounted == false) return;
        unawaited(_loadCommunity());
      },
    );
  }

  Future<void> _loadInitialData({bool forceRefresh = false}) async {
    final shouldAutoOpenCheckIn = !_hasAutoOpenedCheckIn;
    _hasAutoOpenedCheckIn = true;

    // Resolve the pinned-reading preference first so _loadActiveReadings can prefer the
    // pinned reading.
    await _loadPreferences();

    // Start the remaining loads in parallel.
    // _initialLoading will be set to false when the primary reading status is ready.
    final futures = [
      _loadReadStatus(showLoading: false, forceRefresh: forceRefresh).then((_) {
        if (!_disposed && mounted) {
          setState(() {
            _initialLoading = false;
          });
          if (!_readToday && shouldAutoOpenCheckIn) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_disposed && mounted) {
                _openCheckInPage();
              }
            });
          }
        }
      }),
      _loadActiveReadings(),
      _loadCommunity(),
      _loadReflection(),
    ];

    await Future.wait(futures);
  }

  Future<void> _loadActiveReadings() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final snapshot = await widget.activeReadingAggregator.fetch(
        uid,
        today: widget.dateProvider(),
        pinnedReadingId: _pinnedReadingId,
      );
      if (!_disposed && mounted) {
        setState(() {
          _readingsSnapshot = snapshot;
        });
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  /// Loads the user's pinned-reading preference. Best-effort: any failure just
  /// leaves Home's automatic ranking in charge.
  Future<void> _loadPreferences() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final prefs = await widget.userPreferencesService.fetchPreferences(uid);
      if (!_disposed && mounted) {
        setState(() {
          _pinnedReadingId = prefs.pinnedReadingId;
          _autoMarkPlanRead = prefs.autoMarkPlanRead;
        });
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  /// Loads today's saved reflection, if any. Private and independent of the
  /// habit/reading writes — best-effort, any failure just leaves the prompt
  /// card showing.
  Future<void> _loadReflection() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final reflection = await widget.reflectionService.fetchReflection(
        uid,
        _dateKeyFor(widget.dateProvider()),
      );
      if (!_disposed && mounted) {
        setState(() {
          _reflection = reflection?.text;
          _reflectionShared = reflection?.shared ?? false;
        });
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  /// Loads today's community presence — the reader plus the co-members of
  /// their Groups (their Circle, derived per ADR-0003) who have read today —
  /// for the bottom "Your community" glimpse. Best-effort.
  Future<void> _loadCommunity() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    try {
      final coMemberIds =
          await widget.circleService.circleMemberIds(user.uid).timeout(
                const Duration(seconds: 5),
                onTimeout: () => const <String>{},
              );
      final allUids = {user.uid, ...coMemberIds};

      final today = widget.dateProvider();
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      // The feed is per Group (ADR-0004): read the reader's Groups' entries
      // for today and intersect with the Circle, so a stranger's entry can
      // never surface.
      final readLogService = ReadLogService(firestore: widget.firestore);
      final groupIds = await readLogService.groupIdsFor(user.uid).timeout(
            const Duration(seconds: 5),
            onTimeout: () => const <String>[],
          );
      final entriesSnap = await readLogService
          .entriesForGroups(groupIds, dateKey: dateKey)
          .first
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => const <String>[],
          );

      // Resolve display names for the uids that showed up. Member docs and
      // profiles both carry them; the entry itself no longer needs a name —
      // the uid is the identity.
      final nameFutures = <String, Future<String>>{
        for (final uid in entriesSnap)
          if (allUids.contains(uid)) uid: _displayNameFor(uid),
      };
      final names = {
        for (final e in nameFutures.entries) e.key: await e.value,
      };

      final readers = <_CommunityReader>[
        for (final uid in entriesSnap)
          if (allUids.contains(uid))
            _CommunityReader(uid: uid, name: names[uid] ?? ''),
      ];
      readers.sort((a, b) {
        if (a.uid == user.uid) return 1;
        if (b.uid == user.uid) return -1;
        return a.name.compareTo(b.name);
      });

      if (!_disposed && mounted) {
        setState(() {
          _communityReaders = readers;
          _communityTotal = allUids.length;
        });
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  /// Best-effort display name for a uid: member doc first, then profile.
  /// Falls back to '?' so the avatar stack renders a placeholder.
  Future<String> _displayNameFor(String uid) async {
    try {
      final profile = await widget.firestore.collection('users').doc(uid).get();
      final data = profile.data();
      final name = (data?['name'] as String?) ??
          (data?['displayName'] as String?) ??
          (data?['username'] as String?);
      if (name != null && name.isNotEmpty) return name;
    } catch (_) {
      // Best-effort; the glimpse renders a placeholder instead.
    }
    return '?';
  }

  String _dateKeyFor(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
      _watchLiveData();
      unawaited(_loadInitialData());
    }
  }

  /// Fetches today's read flag and calendar history.
  Future<void> _loadReadStatus({
    bool showLoading = true,
    bool forceRefresh = false,
  }) async {
    if (showLoading && !_disposed && mounted) {
      setState(() {
        _toggleLoading = true; // Start loading indicator.
      });
    }

    try {
      final status = await widget.readingStatusService.fetchStatus(
        forceRefresh: forceRefresh,
      );
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

  /// Returns the ranked list of active readings from the current snapshot.
  List<ActiveReadingItem> _buildReadingItems() =>
      _readingsSnapshot.homeReadings;

  /// Marks (or unmarks) the current day as read. Optimistically updates local
  /// state and writes the change to Firestore, rolling back on failure.
  /// [showSnackBar] is disabled when confirming from the check-in page, whose
  /// sun-rise/flood is the confirmation — a floating SnackBar would otherwise
  /// sit on top of the payoff buttons.
  Future<void> _toggleReadStatus({bool showSnackBar = true}) async {
    if (_toggleLoading) return;
    unawaited(widget.vibrationService.mediumImpact());
    final wasRead = _readToday;

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
        if (wasRead) {
          // Optimistically mark today as unread in local state.
          _readToday = false;
          _currentStreak = (prevStreak - 1).clamp(0, double.infinity).toInt();
          _totalReadDays =
              (prevTotalReadDays - 1).clamp(0, double.infinity).toInt();

          if (_pastWeek.length < 7) {
            _pastWeek = List<bool>.generate(
              7,
              (i) => i < _pastWeek.length ? _pastWeek[i] : false,
            );
          } else {
            _pastWeek = List<bool>.from(_pastWeek);
          }
          _pastWeek[weekIndex] = false;

          if (_pastMonth.length < daysInMonth) {
            _pastMonth = List<bool>.generate(
              daysInMonth,
              (i) => i < _pastMonth.length ? _pastMonth[i] : false,
            );
          } else {
            _pastMonth = List<bool>.from(_pastMonth);
          }
          _pastMonth[monthIndex] = false;
          _readDates.removeWhere(
            (d) =>
                d.year == today.year &&
                d.month == today.month &&
                d.day == today.day,
          );
        } else {
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
            _pastWeek = List<bool>.from(_pastWeek);
          }
          _pastWeek[weekIndex] = true;

          if (_pastMonth.length < daysInMonth) {
            _pastMonth = List<bool>.generate(
              daysInMonth,
              (i) => i < _pastMonth.length ? _pastMonth[i] : false,
            );
          } else {
            _pastMonth = List<bool>.from(_pastMonth);
          }
          _pastMonth[monthIndex] = true;
          _readDates.add(DateTime(today.year, today.month, today.day));
        }
      });
    }

    // Reload user before writing to Firestore.
    try {
      await user.reload();
    } catch (_) {}
    final refreshedUser = widget.auth.currentUser ?? user;

    try {
      if (wasRead) {
        await _habitService.clearShowingUp(refreshedUser, date: today);
      } else {
        await _habitService.showUp(refreshedUser, date: today);
      }

      unawaited(_loadReadStatus(showLoading: false));

      // Show a transient SnackBar with an Undo option when marked as read.
      // Skipped when confirming from the check-in page, where the sun-rise and
      // gold flood are the confirmation and the payoff buttons must stay clear.
      // The undo is a single-mark burst: un-marking today reverts the habit
      // itself, so no coupling revert is needed (ADR-0005).
      if (!wasRead && !_disposed && mounted && showSnackBar) {
        _burstUndo.add(context, () {
          _toggleReadStatus();
        });
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to mark reading: $e');
      }
      ErrorLogger.log(e, st);

      if (!_disposed && mounted) {
        // Revert to previous state and notify the user.
        setState(() {
          _readToday = wasRead;
          _pastWeek = prevWeek;
          _pastMonth = prevMonth;
          _readDates = prevReadDates;
          _currentStreak = prevStreak;
          _totalReadDays = prevTotalReadDays;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              wasRead
                  ? 'Failed to undo daily reading. Please try again.'
                  : 'Failed to mark reading. Please try again.',
            ),
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

  /// Updates the progress for [planId] in [_readingsSnapshot] (used for optimistic
  /// updates and rollback when marking a specific plan's reading).
  void _setProgressFor(String planId, UserPlanProgress next) {
    _readingsSnapshot =
        _readingsSnapshot.withOptimisticPlanProgress(planId, next);
  }

  /// Marks (or un-marks) a specific plan's [day] reading. Distinct from the bare
  /// habit tap: this advances the personal plan, and — when the user has opted
  /// in — may also record the daily habit via [PlanCompletionCoordinator]
  /// (one-directional reading→habit coupling). Un-marking never touches the
  /// habit.
  Future<void> _togglePlanReadingFor(
    ReadingPlan plan,
    UserPlanProgress progress,
    int day,
  ) async {
    final user = widget.auth.currentUser;
    if (user == null) return;
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
        _setProgressFor(plan.id, progress.copyWith(completedDays: newDays));
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
        await _habitService.completePlanDayWithBurst(
          context: context,
          user: user,
          planId: plan.id,
          day: day,
          burstController: _burstUndo,
          onUndo: () {
            final p = _readingsSnapshot.activePersonalPlans
                .where((pp) => pp.plan.id == plan.id)
                .firstOrNull;
            if (p != null) {
              _togglePlanReadingFor(p.plan, p.progress, day);
            }
          },
          onMessage: _showSnack,
        );
        unawaited(_loadReadStatus(showLoading: false));
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to update plan reading: $e');
      }
      ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        setState(() => _setProgressFor(plan.id, previousProgress));
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

  /// Whether the current user has marked today's reading complete for [g].
  bool _groupReadToday(ActiveGroupReading g) {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return false;
    for (final m in g.members) {
      if (m.uid == uid) return m.completion >= 1.0;
    }
    return false;
  }

  /// Marks (or unmarks) today's reading for group [g] for the current user via
  /// the shared group progress API, then optimistically reflects it in that
  /// group's member-presence list so the card updates immediately.
  Future<void> _toggleGroupReading(ActiveGroupReading g) async {
    final user = widget.auth.currentUser;
    final today = g.todaySchedule;
    if (user == null || today == null) return;
    if (_groupMarkingIds.contains(g.group.id)) return;

    unawaited(widget.vibrationService.lightImpact());
    final wasRead = _groupReadToday(g);
    final previousSnapshot = _readingsSnapshot;

    if (!_disposed && mounted) {
      setState(() {
        _groupMarkingIds.add(g.group.id);
        _readingsSnapshot = _readingsSnapshot.withOptimisticGroupCompletion(
          g.group.id,
          user.uid,
          wasRead ? 0.0 : 1.0,
        );
      });
    }

    try {
      await widget.groupService.toggleReadStatus(
        groupId: g.group.id,
        uid: user.uid,
        schedule: today,
        read: !wasRead,
      );
      if (!wasRead) {
        if (mounted) {
          await _habitService.coupleWithBurst(
            context: context,
            user: user,
            burstController: _burstUndo,
            onUndo: () {
              final latest = _readingsSnapshot.activeGroupReadings
                  .where((gr) => gr.group.id == g.group.id)
                  .firstOrNull;
              if (latest != null) {
                _toggleGroupReading(latest);
              }
            },
            onMessage: _showSnack,
          );
          unawaited(_loadReadStatus(showLoading: false));
        }
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        setState(() => _readingsSnapshot = previousSnapshot);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update reading. Please try again.'),
          ),
        );
      }
    } finally {
      if (!_disposed && mounted) {
        setState(() => _groupMarkingIds.remove(g.group.id));
      }
    }
  }

  /// Shows a plain fixed SnackBar (used for coupling follow-up messages).
  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      body: RefreshIndicator(
        onRefresh: () => _loadInitialData(forceRefresh: true),
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
              SliverToBoxAdapter(child: _buildMinimalContent(context)),
            ],
          ),
        ),
      ),
    );
  }

  void _openCheckInPage() {
    final isTestEnv = WidgetsBinding.instance.runtimeType
        .toString()
        .toLowerCase()
        .contains('test');

    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration:
            isTestEnv ? Duration.zero : const Duration(milliseconds: 300),
        reverseTransitionDuration:
            isTestEnv ? Duration.zero : const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) => CheckInPage(
          readToday: _readToday,
          seasonDays: _totalReadDays,
          reflection: _reflection,
          dateProvider: widget.dateProvider,
          onConfirmRead: () => _toggleReadStatus(showSnackBar: false),
          onReflect: () {
            // The reflection sheet draws up ON TOP of the check-in screen; the
            // check-in page stays on stage so "Done" (not the reflection) is
            // what returns to Home.
            _openReflectSheet(context, initialText: _reflection);
          },
          onClose: () {
            Navigator.of(context).pop();
          },
          vibrationService: widget.vibrationService,
          enableDriftAnimation: widget.enableDriftAnimation,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// Today's header eyebrow, e.g. `MONDAY · JANUARY 5`.
  String _dateEyebrow(DateTime now) {
    const weekdays = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    const months = [
      'JANUARY',
      'FEBRUARY',
      'MARCH',
      'APRIL',
      'MAY',
      'JUNE',
      'JULY',
      'AUGUST',
      'SEPTEMBER',
      'OCTOBER',
      'NOVEMBER',
      'DECEMBER',
    ];
    return '${weekdays[now.weekday - 1]} · ${months[now.month - 1]} ${now.day}';
  }

  String _greeting(DateTime now) {
    final hour = now.hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
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

    // Rank every active reading (personal + group); the first is the primary
    // hero, the rest fold into compact rows.
    final readingItems = _buildReadingItems();
    final hasPlan = readingItems.isNotEmpty;

    // Home is "the act": the daily habit is the hero, with an optional, clearly
    // secondary "Today's reading" section below it (epic #716, #722/#723).
    // The long-arc plan progress (meter, Day x/y, schedule) lives on Journey.
    final now = widget.dateProvider();
    return SafeArea(
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeader(
            auth: widget.auth,
            firestore: widget.firestore,
            vibrationService: widget.vibrationService,
            dateProvider: widget.dateProvider,
            eyebrow: _dateEyebrow(now),
            title: _greeting(now),
            status: SunMark(
              size: 34,
              done: _readToday,
              onTap: _openCheckInPage,
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.hPadding),
            // Content is top-aligned (habit hero first) and laid out at its
            // natural height; the enclosing CustomScrollView scrolls it when
            // tall.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.gap4),
                if (hasPlan) ...[
                  _buildReadingSection(context, readingItems),
                ] else ...[
                  _buildStartPlanInvitationCard(context),
                ],
                if (_readToday) ...[
                  const SizedBox(height: 24),
                  _buildReflectionSection(context),
                ],
                if (_readToday) ...[
                  const SizedBox(height: AppSpacing.gap24),
                  _buildConsistencyGlimpse(context),
                ],
                // The community glimpse is always present once the user's circle has
                // loaded (matching the prototype), with an empty state when nobody
                // has read yet. `_communityTotal` counts the user, so it is >0 once
                // `_loadCommunity` completes.
                if (_communityTotal > 0) ...[
                  const SizedBox(height: AppSpacing.gap20),
                  _buildCommunitySection(context),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The "Today's reading" section: one auto-chosen primary reading as the hero
  /// (a personal plan, a group, or a wrap-up card for a plan whose window has
  /// ended), every other active plan/group folded into compact rows beneath,
  /// and a "Manage all N plans" affordance.
  Widget _buildReadingSection(
      BuildContext context, List<ActiveReadingItem> items) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primary = items.first;
    final others = items.sublist(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _sectionHeaderHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Today’s reading',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              // Plan management moved to the Path tab (#808): with a single
              // reading the header keeps its schedule link; with several there
              // is no "All plans" affordance — the tab is one tap away.
              if (others.isEmpty)
                TextButton(
                  onPressed: () => _openPrimarySchedule(primary),
                  style: _sectionLinkStyle(colorScheme),
                  child: const Text('Schedule'),
                ),
            ],
          ),
        ),

        // Primary hero.
        if (primary.state == PlanLifecycle.wrapup)
          _buildWrapUpHero(context, primary)
        else ...[
          primary is ActiveGroupReading
              ? _buildGroupReadingCard(context, primary)
              : _buildPersonalReadingCard(context, primary),
          const SizedBox(height: AppSpacing.gap12),
          CatchUpStatusRow(
            status: primary.status,
            // A reader on their own pace overlay is on track with their own
            // dates, not in step with the Group schedule (ADR-0007).
            onTrackLabel: primary.isGroup && !primary.ownPace
                ? 'In step with your group'
                : "You're on track",
            onTap: () => _openPrimarySchedule(primary),
          ),
        ],

        // Other active plans/groups, folded into compact rows.
        for (final it in others) ...[
          const SizedBox(height: AppSpacing.gap12),
          _buildPlanMiniRow(context, it),
        ],
      ],
    );
  }

  /// Section header rows ("Today’s reading", "Your circle") are a fixed 44px
  /// so their trailing link is a full touch target and the gap below the
  /// title is the same with or without a link.
  static const double _sectionHeaderHeight = 44;

  ButtonStyle _sectionLinkStyle(ColorScheme colorScheme) {
    return TextButton.styleFrom(
      foregroundColor: colorScheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gap8),
      minimumSize: const Size(44, _sectionHeaderHeight),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  /// Ghost-style "Mark as read" button — a clear step above the reading card
  /// surface (prototype `.btn-ghost`: `--surface-2` fill + `--border-strong`),
  /// so it reads as a distinct control even in dark mode where the card and a
  /// tonal fill would otherwise share the same luminance.
  ButtonStyle _ghostMarkButtonStyle(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(
      backgroundColor: colorScheme.surfaceContainerLow,
      foregroundColor: colorScheme.onSurface,
      side: BorderSide(color: AppColors.of(context).borderStrong),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.rButton)),
    );
  }

  /// Caption shown beneath a not-yet-read mark button when the "Reading
  /// counts as showing up" preference is on, so marking this reading is known
  /// to also record the daily habit.
  Widget _buildCountsHint(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.wb_sunny_outlined,
          size: AppSpacing.iconSm,
          color: colorScheme.outline,
        ),
        const SizedBox(width: 6),
        Text(
          'Also counts as showing up today',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
        ),
      ],
    );
  }

  /// Non-interactive "already marked" confirmation row — a small primary
  /// check badge + label. Design parity: marking a plan/group reading is
  /// forward-only here; the only way back is the snackbar's "Undo" shown
  /// right after marking (see [_togglePlanReadingFor]/[_toggleGroupReading]) —
  /// there is no standing undo-by-retap.
  Widget _buildReadConfirmationRow(BuildContext context, String label) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primary,
          ),
          alignment: Alignment.center,
          child: Icon(Icons.check,
              size: AppSpacing.iconSm, color: colorScheme.onPrimary),
        ),
        const SizedBox(width: AppSpacing.gap12),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  /// Hero card for a personal plan — the current reading with its own mark.
  Widget _buildPersonalReadingCard(
      BuildContext context, ActiveReadingItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final plan = item.plan!;
    final progress = item.progress!;
    final status = item.status;
    // Only the actual current/missed reading is markable — never a future one.
    // When nothing is due yet (currentEntry == null) the mark button is
    // disabled rather than completing an upcoming reading.
    final entry = status.currentEntry;
    final day = entry?.index;
    final isRead = day != null && progress.completedDays.contains(day);
    final currentRef = _formatReadings(status.currentReadings);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.explore_outlined,
                size: AppSpacing.iconSm,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  plan.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              ),
              if (status.total > 0)
                Text(
                  '${status.doneCount} of ${status.total} read',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.gap8),
          Text(
            currentRef,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: isRead
                ? _buildReadConfirmationRow(context, 'Read · $currentRef')
                : FilledButton.tonalIcon(
                    onPressed: (_planToggleLoading || day == null)
                        ? null
                        : () => _togglePlanReadingFor(plan, progress, day),
                    icon: _planToggleLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Icon(Icons.check_rounded, size: 20),
                    label: const Text('Mark as read'),
                    style: _ghostMarkButtonStyle(context),
                  ),
          ),
          if (!isRead && _autoMarkPlanRead) ...[
            const SizedBox(height: 8),
            _buildCountsHint(context),
          ],
        ],
      ),
    );
  }

  /// Hero card for a group — today's chapters, member presence, "Read with your
  /// community" mark. (The group catch-up row is rendered by the section.)
  Widget _buildGroupReadingCard(BuildContext context, ActiveGroupReading item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final group = item.group;
    final isRead = _groupReadToday(item);
    final canMark = item.todaySchedule != null;
    final refText =
        item.todaySchedule != null && item.todaySchedule!.chapters.isNotEmpty
            ? _formatReadings(item.todaySchedule!.chapters)
            : _formatReadings(item.status.currentReadings);

    // Members who have read today lead the presence stack.
    final readers = item.members.where((m) => m.completion >= 1.0).toList();
    final presenceMembers = [
      ...readers,
      ...item.members.where((m) => m.completion < 1.0),
    ];

    final isMarking = _groupMarkingIds.contains(group.id);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.group_outlined,
                  size: AppSpacing.iconSm, color: colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${group.name} · together',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.gap8),
          Text(
            refText.isEmpty ? 'Rest day' : refText,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          if (readers.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.gap12),
            Row(
              children: [
                MemberPresenceStack(members: presenceMembers, size: 24, max: 4),
                const SizedBox(width: AppSpacing.gap12),
                Expanded(
                  child: Text(
                    _groupPresenceLabel(readers),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: !canMark
                ? OutlinedButton.icon(
                    onPressed: () => _openGroupSchedule(item),
                    icon: Icon(
                      Icons.calendar_today_outlined,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    label: const Text('View schedule'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                      side: BorderSide(
                        color: colorScheme.primary.withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.rButton),
                      ),
                    ),
                  )
                : isRead
                    ? _buildReadConfirmationRow(context, 'Read with your group')
                    : FilledButton.tonalIcon(
                        onPressed:
                            isMarking ? null : () => _toggleGroupReading(item),
                        icon: isMarking
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : const Icon(Icons.check_rounded, size: 20),
                        label: const Text('Read with your group'),
                        style: _ghostMarkButtonStyle(context),
                      ),
          ),
          if (canMark && !isRead && _autoMarkPlanRead) ...[
            const SizedBox(height: 8),
            _buildCountsHint(context),
          ],
        ],
      ),
    );
  }

  /// Hero variant for a plan whose calendar window has ended but isn't finished.
  /// Reframed away from "today / day X of Y" — it's now "finish at your pace."
  /// No "mark done" shortcut: a plan is fully read only when every reading is
  /// marked. A reader who is done anyway can Finish it (ADR-0010), which
  /// leaves the unread readings unmarked.
  Widget _buildWrapUpHero(BuildContext context, ActiveReadingItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = item.status;
    final last = status.lastDate;
    final endedLabel = last == null ? null : _shortDate(last);
    final pct = status.total > 0 ? status.doneCount / status.total : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.eco_outlined,
                  size: AppSpacing.iconSm, color: colorScheme.tertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Plan ended · finish at your pace',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.tertiary,
                  ),
                ),
              ),
              if (endedLabel != null)
                Text(
                  'ended $endedLabel',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.gap8),
          Text(
            item.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${status.remaining} reading${status.remaining == 1 ? '' : 's'} left '
            'of ${status.total}. The window closed, but it stays here until you '
            'finish — no rush.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.gap12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.rSmall),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 7,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.gap8),
              Text(
                '${status.doneCount}/${status.total}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => _openPrimarySchedule(item),
                    icon: const Icon(Icons.eco_outlined, size: 18),
                    label: const Text(
                      'Keep reading',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.rButton),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.gap8),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => _adjustPace(item),
                    icon: const Icon(Icons.speed_outlined,
                        size: AppSpacing.iconSm),
                    label: const Text(
                      'Adjust pace',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.onSurfaceVariant,
                      side: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.4,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.rButton),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: () => _finishReading(item),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurfaceVariant,
              ),
              child: const Text('Finish plan'),
            ),
          ),
        ],
      ),
    );
  }

  /// A compact, non-primary plan/group row.
  Widget _buildPlanMiniRow(BuildContext context, ActiveReadingItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = item.state == PlanLifecycle.behind ||
        item.state == PlanLifecycle.wrapup;
    final tileColor = accent
        ? AppColors.of(context).accentSoft
        : AppColors.of(context).primarySoft;
    final iconColor = accent ? colorScheme.tertiary : colorScheme.primary;
    final IconData icon = item.state == PlanLifecycle.wrapup
        ? Icons.eco_outlined
        : item.isGroup
            ? Icons.group_outlined
            : Icons.explore_outlined;

    // Another plan, so it sits on the card surface; its metrics match the
    // CatchUpStatusRow above so icons, titles and chevrons line up.
    return Material(
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.rInset),
        side: BorderSide(color: AppColors.of(context).border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openPrimarySchedule(item),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.gap12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tileColor,
                  borderRadius: BorderRadius.circular(AppSpacing.rChip),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: AppSpacing.iconSm, color: iconColor),
              ),
              const SizedBox(width: AppSpacing.gap12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.isGroup ? '${item.title} · together' : item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _miniStatusText(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: accent
                            ? colorScheme.tertiary
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.gap8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Status line for a [_buildPlanMiniRow].
  String _miniStatusText(ActiveReadingItem item) {
    final s = item.status;
    final ref = _formatReadings(s.currentReadings);
    switch (item.state) {
      case PlanLifecycle.due:
        return 'Today · $ref';
      case PlanLifecycle.behind:
        return '${s.missedCount} behind · $ref';
      case PlanLifecycle.wrapup:
        return 'Ended · ${s.remaining} reading${s.remaining == 1 ? '' : 's'} left';
      case PlanLifecycle.ontrack:
      case PlanLifecycle.complete:
        return 'On track · $ref';
    }
  }

  /// `Mon D` (no year) for the wrap-up "ended" label.
  String _shortDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  /// Adjust pace on the Plan ended card — the same flow as Path's plan menu.
  /// A personal plan's schedule is rewritten in place; a Shared plan only
  /// gets the reader's own pace overlay (ADR-0007). A schedule rewrite
  /// doesn't touch `plan_progress`, so the plans are reloaded afterwards.
  Future<void> _adjustPace(ActiveReadingItem item) async {
    final uid = widget.auth.currentUser?.uid;
    final group = item.group;
    if (uid != null && group != null) {
      final applied = await adjustSharedPace(
        context,
        firestore: widget.firestore,
        uid: uid,
        groupId: group.id,
        schedule: item.schedule,
        completedDateIds: item.completedDateIds,
        daysBehind: item.status.missedCount,
        today: widget.dateProvider(),
        vibrationService: widget.vibrationService,
      );
      if (applied && !_disposed && mounted) await _loadActiveReadings();
      return;
    }
    final plan = item.plan;
    final progress = item.progress;
    if (uid == null || plan == null || progress == null) return;
    final applied = await adjustPersonalPace(
      context,
      firestore: widget.firestore,
      uid: uid,
      plan: plan,
      progress: progress,
      today: widget.dateProvider(),
      vibrationService: widget.vibrationService,
    );
    if (applied && !_disposed && mounted) await _loadActiveReadings();
  }

  /// Finishes the ended plan on the card (ADR-0010) — personal, optimistic
  /// and undoable. The plan leaves Home at once and returns if the write
  /// fails; unread readings stay unmarked.
  Future<void> _finishReading(ActiveReadingItem item) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    unawaited(widget.vibrationService.lightImpact());
    final group = item.group;
    final plan = item.plan;
    final previousSnapshot = _readingsSnapshot;
    setState(() {
      _readingsSnapshot = _readingsSnapshot.withoutReading(item.pinKey);
    });
    try {
      if (group != null) {
        await widget.groupService.finishMemberParticipation(
          groupId: group.id,
          uid: uid,
        );
      } else {
        await widget.readingPlanService.finishPlan(uid, plan!.id);
      }
      if (_disposed || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Finished "${item.title}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _unfinishReading(item),
          ),
        ),
      );
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (_disposed || !mounted) return;
      setState(() {
        _readingsSnapshot = previousSnapshot;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to finish "${item.title}". Please try again.'),
        ),
      );
    }
  }

  /// Undoes [_finishReading]; the live plan/group streams bring it back.
  Future<void> _unfinishReading(ActiveReadingItem item) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final group = item.group;
      if (group != null) {
        await widget.groupService.unfinishMemberParticipation(
          groupId: group.id,
          uid: uid,
        );
      } else {
        await widget.readingPlanService.unfinishPlan(uid, item.plan!.id);
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (_disposed || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to restore "${item.title}". Please try again.'),
        ),
      );
    }
  }

  /// Opens the schedule/detail for any reading item (personal plan or group).
  void _openPrimarySchedule(ActiveReadingItem item) {
    if (item is ActiveGroupReading) {
      _openGroupSchedule(item);
      return;
    }
    _openPlanScheduleFor(item.plan!, item.progress!);
  }

  void _openPlanScheduleFor(ReadingPlan plan, UserPlanProgress progress) {
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

  /// The richer "no active reading at all" invitation card — used only when
  /// there's no plan or group to show at all. It leads to the Path tab, where
  /// the labelled start action lives (#808).
  Widget _buildStartPlanInvitationCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        side: BorderSide(color: AppColors.of(context).border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onOpenJourney?.call(),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.of(context).primarySoft,
                  borderRadius: BorderRadius.circular(AppSpacing.rInset),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.explore_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.gap12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Start a reading plan',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Optional — a gentle rhythm to read by, on your own '
                      'or together.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _groupPresenceLabel(List<GroupMemberProgressData> readers) {
    if (readers.isEmpty) return 'Be the first to read this';
    final names = readers.take(2).map((r) => r.name.split(' ').first).toList();
    final more = readers.length - names.length;
    final suffix = more > 0 ? ' & $more other${more > 1 ? 's' : ''}' : '';
    return '${names.join(', ')}$suffix read today';
  }

  void _openGroupSchedule(ActiveGroupReading g) {
    unawaited(widget.vibrationService.lightImpact());
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlanDetailPage(
          group: g.group,
          groupService: widget.groupService,
          auth: widget.auth,
          vibrationService: widget.vibrationService,
          initialSchedule: g.schedule,
          isMember: true,
        ),
      ),
    );
  }

  /// The optional daily reflection — a saved-entry card with an Edit action,
  /// or a prompt card that opens the editor. Only shown once the habit is
  /// marked read (#747); saving/skipping never touches the habit mark itself.
  Widget _buildReflectionSection(BuildContext context) {
    final reflection = _reflection;
    if (reflection != null && reflection.isNotEmpty) {
      return _buildSavedReflectionCard(context, reflection);
    }
    return _buildReflectionPromptCard(context);
  }

  Widget _buildSavedReflectionCard(BuildContext context, String text) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _reflectionShared
                      ? 'YOUR REFLECTION · SHARED WITH YOUR CIRCLE'
                      : 'YOUR REFLECTION',
                  style: AppTextStyles.caption(context).copyWith(
                    color: _reflectionShared
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _openReflectSheet(context, initialText: text),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.gap8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.format_quote_rounded,
                size: 20,
                color: colorScheme.primary.withValues(alpha: 0.5),
              ),
              const SizedBox(width: AppSpacing.gap12),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFamily: AppTheme.fontSerif,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReflectionPromptCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final prompt = reflectionPromptFor(widget.dateProvider());
    return Material(
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        side: BorderSide(color: AppColors.of(context).border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openReflectSheet(context, initialText: null),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.of(context).accentSoft,
                  borderRadius: BorderRadius.circular(AppSpacing.rInset),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.edit_note_rounded,
                  size: AppSpacing.iconLg,
                  color: theme.colorScheme.tertiary,
                ),
              ),
              const SizedBox(width: AppSpacing.gap12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Take a moment',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      prompt,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the reflection editor. Saving/skipping is entirely independent of
  /// the daily habit mark — this is only ever reachable once that's already
  /// happened. A saved entry opens with its current share state; a fresh one
  /// always starts unshared (#807).
  Future<void> _openReflectSheet(
    BuildContext context, {
    required String? initialText,
  }) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    final dateKey = _dateKeyFor(widget.dateProvider());
    final savedReflection = await widget.reflectionService.fetchReflection(
      uid,
      dateKey,
    );
    if (!mounted || !context.mounted) return;
    await showReflectSheet(
      context,
      initialText: initialText,
      prompt: reflectionPromptFor(widget.dateProvider()),
      initialShared: savedReflection?.shared ?? false,
      onSave: (text, share) async {
        await widget.reflectionService.saveReflection(
          uid,
          dateKey,
          text,
          share: share,
        );
        if (!_disposed && mounted) {
          setState(() {
            _reflection = text;
            _reflectionShared = share;
          });
        }
      },
    );
  }

  /// The design's "consistency glimpse" — a tappable record of showing up
  /// (week-dots + season count) that opens the Journey tab. Describes the
  /// *habit*, not plan progress.
  Widget _buildConsistencyGlimpse(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Material(
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        side: BorderSide(color: AppColors.of(context).border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpenJourney,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.cardPadding,
            vertical: AppSpacing.gap16,
          ),
          child: Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    _weekDot(
                      context,
                      labels[i],
                      _readOnWeekday(i == 0 ? 7 : i),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: AppSpacing.gap12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Here $_totalReadDays day${_totalReadDays == 1 ? '' : 's'} this season',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Whenever you return, it's enough.",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Whether the user read on the given ISO weekday (Mon=1..Sun=7). [_pastWeek]
  /// is indexed by `weekday % 7` (Sun=0), matching [_toggleReadStatus].
  bool _readOnWeekday(int weekday) {
    final idx = weekday % 7;
    return idx < _pastWeek.length && _pastWeek[idx];
  }

  Widget _weekDot(BuildContext context, String label, bool read) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: read ? colorScheme.primary : Colors.transparent,
            border: read
                ? null
                : Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.outline,
                letterSpacing: 0,
              ),
        ),
      ],
    );
  }

  /// The bottom "Your community" glimpse: who among the reader's Circle —
  /// the co-members of their Groups — has read today. Tapping opens the
  /// Community tab.
  Widget _buildCommunitySection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final readers = _communityReaders;

    String firstName(_CommunityReader r) {
      final first = r.name.split(' ').first;
      return first.isEmpty ? 'Someone' : first;
    }

    final String subtitle;
    if (readers.isEmpty) {
      subtitle = 'Be the first to show up today';
    } else if (readers.length == 1) {
      subtitle = '${firstName(readers.first)} showed up — join them';
    } else if (readers.length == 2) {
      subtitle = '${firstName(readers[0])} & ${firstName(readers[1])} '
          'showed up';
    } else {
      subtitle = '${firstName(readers[0])}, ${firstName(readers[1])} '
          '& ${readers.length - 2} more';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _sectionHeaderHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Your circle',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              TextButton(
                onPressed: widget.onOpenCommunity,
                style: _sectionLinkStyle(colorScheme),
                child: const Text('Open'),
              ),
            ],
          ),
        ),
        Material(
          color: colorScheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.rCard),
            side: BorderSide(color: AppColors.of(context).border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onOpenCommunity,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Row(
                children: [
                  MemberPresenceStack(
                    members: readers
                        .map(
                          (r) => GroupMemberProgressData(
                            uid: r.uid,
                            name: r.name,
                            completion: 1.0,
                          ),
                        )
                        .toList(),
                    size: 36,
                    max: 5,
                    showDoneBadge: false,
                  ),
                  const SizedBox(width: AppSpacing.gap12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${readers.length} of $_communityTotal read today',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _burstUndo.dispose();
    _animationController.dispose();
    _syncSub?.cancel();
    _readingsSub?.cancel();
    _statusSub?.cancel();
    _reflectionSub?.cancel();
    _communityFeedSub?.cancel();
    _communityRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;
}

/// Lightweight record of a person who has read today, for the Home community
/// glimpse. Only the fields the glimpse needs (uid + name) are loaded.
class _CommunityReader {
  final String uid;
  final String name;

  const _CommunityReader({required this.uid, required this.name});
}
