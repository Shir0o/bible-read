import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/error_logger.dart';
import '../services/friend_service.dart';
import '../services/google_sign_in_factory.dart';
import '../services/bible_progress_service.dart';
import '../services/catch_up_engine.dart';
import '../services/group_service.dart';
import '../services/plan_completion_coordinator.dart';
import '../services/reading_plan_service.dart';
import '../services/reading_status_service.dart';
import '../services/user_preferences_service.dart';
import '../models/group.dart';
import '../models/group_member_progress.dart';
import '../models/group_schedule.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';

import '../services/vibration_service.dart';
import '../widgets/catch_up_status_row.dart';
import '../widgets/common_styles.dart'; // Kept for AppTextStyles if used, or verify usage. Check minimal usage.
import '../theme/app_theme.dart';
import '../widgets/member_presence_stack.dart';
import '../widgets/navigation_menu_scope.dart';
import '../widgets/new_plan_picker_sheet.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/skeletons/home_page_skeleton.dart';
import 'all_plans_page.dart';
import 'create_group_page.dart';
import 'create_plan_page.dart';
import 'full_schedule_page.dart';
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
    this.onOpenJourney,
    this.onOpenCommunity,
    ReadingStatusService? readingStatusService,
    VibrationService? vibrationService,
    GoogleSignIn Function()? googleSignInProvider,
    BibleProgressService? bibleProgressService,
    ReadingPlanService? readingPlanService,
    UserPreferencesService? userPreferencesService,
    GroupService? groupService,
    FriendService? friendService,
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
            bibleProgressService ?? BibleProgressService(firestore: firestore),
        groupService = groupService ??
            GroupService(firestore: firestore ?? FirebaseFirestore.instance),
        friendService = friendService ??
            FriendService(firestore: firestore ?? FirebaseFirestore.instance);

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

  /// Loads the user's group, its schedule and member presence for the
  /// "together" reading card (design parity — Home group plan section).
  final GroupService groupService;

  /// Loads friends so Home can show the "Your community" presence glimpse.
  final FriendService friendService;

  /// Switches to the Journey tab when the consistency glimpse is tapped.
  final VoidCallback? onOpenJourney;

  /// Switches to the Community tab when the community glimpse is tapped.
  final VoidCallback? onOpenCommunity;

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

  // Plan state. *All* active personal plans (plan + progress) are retained so
  // Home can rank every active reading, pick a single primary hero, and fold
  // the rest into compact rows — plus surface a "wrap-up" hero for any plan
  // whose calendar window has ended but isn't yet content-complete (#716).
  StreamSubscription<DocumentSnapshot>? _syncSub;

  /// Subscription to the active-plans stream, cancelled on dispose.
  StreamSubscription<List<UserPlanProgress>>? _activePlansSub;

  /// Timers/subscriptions created by best-effort loads, tracked so they can be
  /// cancelled on dispose (otherwise a slow stream's timeout Timer can outlive
  /// the widget and trip the "Timer still pending" test invariant).
  final Set<Timer> _loadTimers = {};
  final Set<StreamSubscription<dynamic>> _loadSubs = {};

  List<_PersonalPlan> _personalPlans = [];

  /// Whether the primary plan card's mark is mid-write.
  bool _planToggleLoading = false;

  // Group state. Powers the "together" reading cards under Today's reading: every
  // group the user belongs to, each with today's scheduled chapters, member
  // presence and the catch-up set used by the shared CatchUpStatusRow. Keyed by
  // group id; insertion order is preserved so ranking stays stable.
  final Map<String, _GroupData> _groups = {};

  // Community presence. The bottom "Your community" glimpse — who among the
  // user and their friends has read today.
  List<_CommunityReader> _communityReaders = [];
  int _communityTotal = 0;

  /// The reading the user pinned as "Primary on Home" (typed key
  /// `plan:<id>` / `group:<id>`), or `null` to let ranking auto-pick the hero.
  /// Set from the All Plans hub; honored in [_buildReadingItems].
  String? _pinnedReadingId;

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
    // Resolve the pinned-reading preference first so _loadGroup can prefer the
    // pinned group (Home only surfaces one group, so it must load the right one).
    await _loadPreferences();

    // Start the remaining loads in parallel.
    // _initialLoading will be set to false when the primary reading status is ready.
    final futures = [
      _loadReadStatus(showLoading: false).then((_) {
        if (!_disposed && mounted) {
          setState(() {
            _initialLoading = false;
          });
        }
      }),
      _loadActivePlans(),
      _loadGroup(),
      _loadCommunity(),
    ];

    await Future.wait(futures);
  }

  /// Loads the user's pinned-reading preference. Best-effort: any failure just
  /// leaves Home's automatic ranking in charge.
  Future<void> _loadPreferences() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final prefs = await widget.userPreferencesService.fetchPreferences(uid);
      if (!_disposed && mounted) {
        setState(() => _pinnedReadingId = prefs.pinnedReadingId);
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  /// Resolves with the first value of [stream], falling back to [fallback] after
  /// [timeout]. Unlike `stream.first.timeout(...)`, the timer and subscription
  /// are owned and tracked so they are cancelled on dispose rather than leaking.
  Future<T> _firstWithTimeout<T>(
    Stream<T> stream, {
    required Duration timeout,
    required T fallback,
  }) {
    final completer = Completer<T>();
    StreamSubscription<T>? sub;
    Timer? timer;

    void finish(T value) {
      if (completer.isCompleted) return;
      final t = timer;
      if (t != null) {
        t.cancel();
        _loadTimers.remove(t);
      }
      final s = sub;
      if (s != null) {
        _loadSubs.remove(s);
        s.cancel();
      }
      completer.complete(value);
    }

    timer = Timer(timeout, () => finish(fallback));
    _loadTimers.add(timer);
    sub = stream.listen(
      finish,
      onError: (_) => finish(fallback),
      onDone: () => finish(fallback),
    );
    _loadSubs.add(sub);
    return completer.future;
  }

  /// Loads the user's first group, today's scheduled chapters, member presence
  /// and the catch-up set. Best-effort: any failure simply hides the section.
  Future<void> _loadGroup() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final groups = await _firstWithTimeout<List<Group>>(
        widget.groupService.groupsForUser(uid),
        timeout: const Duration(seconds: 5),
        fallback: const <Group>[],
      );
      if (groups.isEmpty) {
        if (!_disposed && mounted) {
          setState(() => _groups.clear());
        }
        return;
      }

      final today = _dateOnly(widget.dateProvider());

      // Load every group the user belongs to in parallel — each group's
      // schedule, today's member presence, and the user's per-chapter progress —
      // so they can all participate in the Today's-reading hero/list ranking.
      final loaded = await Future.wait(groups.map((group) async {
        final results = await Future.wait([
          _firstWithTimeout<List<GroupSchedule>>(
            widget.groupService.schedule(group.id),
            timeout: const Duration(seconds: 3),
            fallback: const <GroupSchedule>[],
          ),
          _firstWithTimeout<List<GroupMemberProgressData>>(
            widget.groupService
                .memberDailyCompletion(group.id, includeUid: uid),
            timeout: const Duration(seconds: 3),
            fallback: const <GroupMemberProgressData>[],
          ),
          _firstWithTimeout<Map<String, int>>(
            widget.groupService.userProgressForGroup(group.id, uid),
            timeout: const Duration(seconds: 3),
            fallback: const <String, int>{},
          ),
        ]);

        final schedule = results[0] as List<GroupSchedule>;
        final members = results[1] as List<GroupMemberProgressData>;
        final progress = results[2] as Map<String, int>;

        GroupSchedule? todayEntry;
        for (final s in schedule) {
          if (_dateOnly(s.date) == today) {
            todayEntry = s;
            break;
          }
        }

        return _GroupData(
          group: group,
          schedule: schedule,
          today: todayEntry,
          members: members,
          completedDateIds: progress.entries
              .where((e) => e.value > 0)
              .map((e) => e.key)
              .toSet(),
        );
      }));

      if (!_disposed && mounted) {
        setState(() {
          _groups
            ..clear()
            ..addEntries(loaded.map((g) => MapEntry(g.group.id, g)));
        });
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  /// Loads today's community presence — the user plus friends who have read
  /// today — for the bottom "Your community" glimpse. Best-effort.
  Future<void> _loadCommunity() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    try {
      final friends = await _firstWithTimeout<List<Friend>>(
        widget.friendService.friends(user.uid),
        timeout: const Duration(seconds: 5),
        fallback: const <Friend>[],
      );
      final allUids = {user.uid, ...friends.map((f) => f.uid)};

      final today = widget.dateProvider();
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final entriesSnap = await widget.firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .get();

      final readers = <_CommunityReader>[];
      for (final doc in entriesSnap.docs) {
        if (!allUids.contains(doc.id)) continue;
        final name = (doc.data()['name'] ?? '').toString();
        readers.add(_CommunityReader(uid: doc.id, name: name));
      }
      // Show the current user last so friends lead the stack.
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

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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

  /// Loads *every* active (non-archived) personal plan with its plan document,
  /// so Home can rank them and choose a primary. Streams updates so marking a
  /// reading re-ranks live.
  Future<void> _loadActivePlans() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;

    final completer = Completer<void>();
    bool firstEvent = true;

    _activePlansSub?.cancel();
    _activePlansSub = widget.readingPlanService.getActivePlans(uid).listen(
      (progresses) async {
        if (progresses.isEmpty) {
          if (!_disposed && mounted) {
            setState(() => _personalPlans = []);
          }
          if (firstEvent) {
            firstEvent = false;
            completer.complete();
          }
          return;
        }

        final items = <_PersonalPlan>[];
        for (final progress in progresses) {
          final plan = await widget.readingPlanService.getPlanById(
            progress.planId,
            userId: uid,
          );
          if (plan != null) {
            items.add(_PersonalPlan(plan: plan, progress: progress));
          }
        }

        if (!_disposed && mounted) {
          setState(() => _personalPlans = items);
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

  /// Builds the ranked list of active readings (personal plans + my group),
  /// dropping any that are content-complete. Ordered by how pressing each is —
  /// due → behind → on-track → ended — so the first item is the primary hero.
  List<_ReadingItem> _buildReadingItems() {
    final today = widget.dateProvider();
    final items = <_ReadingItem>[];

    for (final pp in _personalPlans) {
      final status = CatchUpEngine.forPersonalPlan(
        pp.plan,
        pp.progress,
        today: today,
      );
      final state = status.lifecycleAt(today);
      if (state == PlanLifecycle.complete) continue;
      items.add(_ReadingItem.personal(pp.plan, pp.progress, status, state));
    }

    for (final g in _groups.values) {
      if (g.schedule.isEmpty) continue;
      final status = CatchUpEngine.forGroupSchedule(
        g.schedule,
        g.completedDateIds,
        today: today,
      );
      final state = status.lifecycleAt(today);
      if (state != PlanLifecycle.complete) {
        items.add(_ReadingItem.group(g.group, status, state));
      }
    }

    const rank = {
      PlanLifecycle.due: 0,
      PlanLifecycle.behind: 1,
      PlanLifecycle.ontrack: 2,
      PlanLifecycle.wrapup: 3,
    };
    items.sort((a, b) {
      final r = rank[a.state]! - rank[b.state]!;
      if (r != 0) return r;
      return b.status.missedCount - a.status.missedCount;
    });

    // A user-pinned reading overrides the automatic ranking and becomes the
    // hero, matching the "Primary on Home" pin in the All Plans hub.
    final pinned = _pinnedReadingId;
    if (pinned != null) {
      final idx = items.indexWhere((it) => it.pinKey == pinned);
      if (idx > 0) {
        final hero = items.removeAt(idx);
        items.insert(0, hero);
      }
    }
    return items;
  }

  /// Marks (or unmarks) the current day as read. Optimistically updates local
  /// state and writes the change to Firestore, rolling back on failure.
  Future<void> _toggleReadStatus() async {
    if (_toggleLoading) return;
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
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
          _readDates.removeWhere((d) =>
              d.year == today.year &&
              d.month == today.month &&
              d.day == today.day);
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
    final refreshedUser = widget.auth.currentUser;

    try {
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      if (wasRead) {
        final List<Future<void>> backendWrites = [
          widget.firestore
              .collection('read_logs')
              .doc(dateKey)
              .collection('entries')
              .doc(user.uid)
              .delete(),
          widget.firestore
              .collection('users')
              .doc(user.uid)
              .collection('reading')
              .doc(dateKey)
              .set({'read': false}, SetOptions(merge: true)),
        ];
        await Future.wait(backendWrites);
      } else {
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
        await Future.wait(backendWrites);
      }

      // Update summary collection (lightweight update)
      await _updateSummaryWithToday();

      // Invalidate cache so the next tab visit fetches fresh data.
      widget.readingStatusService.invalidateCache();
      unawaited(_loadReadStatus(showLoading: false));

      // Show non-auto-dismissing SnackBar with Undo option when marked as read.
      if (!wasRead && !_disposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Daily reading marked as complete'),
            duration: const Duration(days: 365),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                _toggleReadStatus();
              },
            ),
          ),
        );
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
            content: Text(wasRead
                ? 'Failed to undo daily reading. Please try again.'
                : 'Failed to mark reading. Please try again.'),
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

  /// Replaces the progress for [planId] in [_personalPlans] (used for optimistic
  /// updates and rollback when marking a specific plan's reading).
  void _setProgressFor(String planId, UserPlanProgress next) {
    _personalPlans = _personalPlans
        .map((pp) => pp.plan.id == planId
            ? _PersonalPlan(plan: pp.plan, progress: next)
            : pp)
        .toList();
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
        await _completionCoordinator.completePlanDay(
          context: context,
          user: user,
          planId: plan.id,
          day: day,
        );
        // The coupling may have recorded the habit; refresh habit state.
        widget.readingStatusService.invalidateCache();
        unawaited(_loadReadStatus(showLoading: false));

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Day $day of "${plan.title}" marked as read.'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () {
                  final p =
                      _personalPlans.firstWhere((pp) => pp.plan.id == plan.id);
                  _togglePlanReadingFor(p.plan, p.progress, day);
                },
              ),
            ),
          );
        }
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
  bool _groupReadToday(_GroupData g) {
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
  Future<void> _toggleGroupReading(_GroupData g) async {
    final user = widget.auth.currentUser;
    final today = g.today;
    if (user == null || today == null) return;
    if (g.markLoading) return;

    unawaited(widget.vibrationService.lightImpact());
    final wasRead = _groupReadToday(g);
    final previousMembers = List<GroupMemberProgressData>.from(g.members);

    if (!_disposed && mounted) {
      setState(() {
        g.markLoading = true;
        g.members = g.members
            .map((m) => m.uid == user.uid
                ? GroupMemberProgressData(
                    uid: m.uid,
                    name: m.name,
                    photoUrl: m.photoUrl,
                    completion: wasRead ? 0.0 : 1.0,
                  )
                : m)
            .toList();
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
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Group reading marked as complete.'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => _toggleGroupReading(g),
              ),
            ),
          );
        }
        if (!mounted) return;
        await _completionCoordinator.maybeCoupleHabit(
          context: context,
          user: user,
          onMessage: (message) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          },
        );
        widget.readingStatusService.invalidateCache();
        unawaited(_loadReadStatus(showLoading: false));
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        setState(() => g.members = previousMembers);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update reading. Please try again.'),
          ),
        );
      }
    } finally {
      if (!_disposed && mounted) {
        setState(() => g.markLoading = false);
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
      body: RefreshIndicator(
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
    );
  }

  /// The design's Home top bar: an eyebrow date, a serif-style greeting (no
  /// name) and a tappable avatar on the right that opens the navigation menu.
  Widget _buildHomeHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = widget.auth.currentUser;
    final now = widget.dateProvider();

    const weekdays = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY'
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
      'DECEMBER'
    ];
    final eyebrow =
        '${weekdays[now.weekday - 1]} · ${months[now.month - 1]} ${now.day}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  eyebrow,
                  style: AppTextStyles.caption(context).copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _greeting(now),
                  style: AppTextStyles.title(context).copyWith(
                    fontSize: 27,
                    fontWeight: FontWeight.w500,
                    height: 1.05,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            button: true,
            label: 'Open menu',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                widget.vibrationService.lightImpact();
                NavigationMenuScope.maybeOf(context)?.showMenu(context);
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primaryContainer,
                  image: user?.photoURL != null
                      ? DecorationImage(
                          image: CachedNetworkImageProvider(user!.photoURL!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: user?.photoURL == null
                    ? Text(
                        _userInitial(user),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _greeting(DateTime now) {
    final hour = now.hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _userInitial(User? user) {
    final name = (user?.displayName ?? '').trim();
    if (name.isNotEmpty) return name[0].toUpperCase();
    final email = (user?.email ?? '').trim();
    if (email.isNotEmpty) return email[0].toUpperCase();
    return '?';
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
            _buildHomeHeader(context),
            const SizedBox(height: 16),
            _buildHabitHero(context, hasPlan: hasPlan),
            if (hasPlan) ...[
              const SizedBox(height: 28),
              _buildReadingSection(context, readingItems),
            ] else ...[
              const SizedBox(height: 16),
              _buildStartNewPlanButton(context),
            ],
            if (_readToday) ...[
              const SizedBox(height: 40),
              _buildConsistencyGlimpse(context),
            ],
            // The community glimpse is always present once the user's circle has
            // loaded (matching the prototype), with an empty state when nobody
            // has read yet. `_communityTotal` counts the user, so it is >0 once
            // `_loadCommunity` completes.
            if (_communityTotal > 0) ...[
              const SizedBox(height: 32),
              _buildCommunitySection(context),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Filled lavender medallion with concentric rings + glow — the "small reward"
  /// shown when the daily habit is marked (the design's affirm state).
  Widget _buildAffirmMedallion(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final line = AppColors.of(context).primaryLine;
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer concentric ring (faint).
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: line.withValues(alpha: 0.18)),
            ),
          ),
          // Inner concentric ring.
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: line.withValues(alpha: 0.32)),
            ),
          ),
          // The medallion itself — solid primary with a soft glow.
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primary,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.45),
                  blurRadius: 28,
                  spreadRadius: -10,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Icon(
              Icons.check_rounded,
              size: 31,
              color: colorScheme.onPrimary,
            ),
          ),
        ],
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
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.75),
                  radius: 1.15,
                  colors: [
                    colorScheme.surfaceContainerLowest,
                    colorScheme.primaryContainer,
                  ],
                  stops: const [0.0, 0.85],
                ),
                borderRadius: BorderRadius.circular(AppSpacing.rCard),
                border: Border.all(
                  color: AppColors.of(context).primaryLine,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildAffirmMedallion(context),
                  const SizedBox(height: 16),
                  Text(
                    'Thank you for being here',
                    style: AppTextStyles.title(context).copyWith(
                      fontSize: 26,
                      fontWeight: FontWeight.w500,
                      height: 1.12,
                      color: colorScheme.onSurface,
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
                color: AppColors.of(context).primarySoft,
                borderRadius: BorderRadius.circular(AppSpacing.rCard),
                border: Border.all(
                  color: AppColors.of(context).primaryLine,
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
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
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

  /// The "Today's reading" section: one auto-chosen primary reading as the hero
  /// (a personal plan, a group, or a wrap-up card for a plan whose window has
  /// ended), every other active plan/group folded into compact rows beneath,
  /// and a "Manage all N plans" affordance.
  Widget _buildReadingSection(BuildContext context, List<_ReadingItem> items) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primary = items.first;
    final others = items.sublist(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Today’s reading',
              style: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextButton(
              onPressed: others.isNotEmpty
                  ? () => _openReadingPlansHub()
                  : () => _openPrimarySchedule(primary),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(others.isNotEmpty ? 'All plans' : 'Schedule'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Primary hero.
        if (primary.state == PlanLifecycle.wrapup)
          _buildWrapUpHero(context, primary)
        else ...[
          primary.isGroup
              ? _buildGroupReadingCard(context, primary)
              : _buildPersonalReadingCard(context, primary),
          const SizedBox(height: 10),
          CatchUpStatusRow(
            status: primary.status,
            onTrackLabel: primary.isGroup
                ? 'In step with your community'
                : "You're on track",
            onTap: () => _openPrimarySchedule(primary),
          ),
        ],

        // Other active plans/groups, folded into compact rows.
        for (final it in others) ...[
          const SizedBox(height: 10),
          _buildPlanMiniRow(context, it),
        ],

        // Always offer to start another plan, no matter how many are active.
        const SizedBox(height: 14),
        _buildStartNewPlanButton(context),
      ],
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
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  /// Hero card for a personal plan — the current reading with its own mark.
  Widget _buildPersonalReadingCard(BuildContext context, _ReadingItem item) {
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(
          color: AppColors.of(context).border,
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
                  plan.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (status.total > 0)
                Text(
                  '${status.doneCount} of ${status.total} read',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _formatReadings(status.currentReadings),
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
                    onPressed: _planToggleLoading
                        ? null
                        : () => _togglePlanReadingFor(plan, progress, day),
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
        ],
      ),
    );
  }

  /// Hero card for a group — today's chapters, member presence, "Read with your
  /// community" mark. (The group catch-up row is rendered by the section.)
  Widget _buildGroupReadingCard(BuildContext context, _ReadingItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final group = item.group!;
    final g = _groups[group.id];
    if (g == null) return const SizedBox.shrink();
    final isRead = _groupReadToday(g);
    final canMark = g.today != null;
    final refText = g.today != null && g.today!.chapters.isNotEmpty
        ? _formatReadings(g.today!.chapters)
        : _formatReadings(item.status.currentReadings);

    // Members who have read today lead the presence stack.
    final readers = g.members.where((m) => m.completion >= 1.0).toList();
    final presenceMembers = [
      ...readers,
      ...g.members.where((m) => m.completion < 1.0),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(
          color: AppColors.of(context).border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.group_outlined, size: 14, color: colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${group.name} · together',
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
            refText.isEmpty ? 'Rest day' : refText,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          if (readers.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                MemberPresenceStack(members: presenceMembers, size: 24, max: 4),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _groupPresenceLabel(readers),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
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
                    onPressed: () => _openGroupSchedule(g),
                    icon: Icon(Icons.calendar_today_outlined,
                        size: 18, color: colorScheme.primary),
                    label: const Text('View schedule'),
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
                : isRead
                    ? OutlinedButton.icon(
                        onPressed:
                            g.markLoading ? null : () => _toggleGroupReading(g),
                        icon: Icon(Icons.check_circle,
                            size: 20, color: colorScheme.primary),
                        label: const Text('Read with your community'),
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
                            g.markLoading ? null : () => _toggleGroupReading(g),
                        icon: g.markLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : const Icon(Icons.check_rounded, size: 20),
                        label: const Text('Read with your community'),
                        style: _ghostMarkButtonStyle(context),
                      ),
          ),
        ],
      ),
    );
  }

  /// Hero variant for a plan whose calendar window has ended but isn't finished.
  /// Reframed away from "today / day X of Y" — it's now "finish at your pace."
  /// No "mark done" shortcut: a plan only closes when every reading is read.
  Widget _buildWrapUpHero(BuildContext context, _ReadingItem item) {
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
        border: Border.all(
          color: AppColors.of(context).border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.eco_outlined, size: 14, color: colorScheme.tertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Plan ended · finish at your pace',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.tertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (endedLabel != null)
                Text(
                  'ended $endedLabel',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w500,
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
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 7,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(colorScheme.primary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${status.doneCount}/${status.total}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
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
                    label: const Text('Keep reading'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
              if (!item.isGroup) ...[
                const SizedBox(width: 9),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => _openPrimarySchedule(item),
                    icon: const Icon(Icons.calendar_today_outlined, size: 17),
                    label: const Text('Reschedule'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.onSurfaceVariant,
                      side: BorderSide(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// A compact, non-primary plan/group row.
  Widget _buildPlanMiniRow(BuildContext context, _ReadingItem item) {
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

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openPrimarySchedule(item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tileColor,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
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
                        fontWeight: FontWeight.w600,
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
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Status line for a [_buildPlanMiniRow].
  String _miniStatusText(_ReadingItem item) {
    final s = item.status;
    final ref = _formatReadings(s.currentReadings);
    switch (item.state) {
      case PlanLifecycle.due:
        return 'Today · $ref';
      case PlanLifecycle.behind:
        return '${s.missedCount} behind · $ref';
      case PlanLifecycle.wrapup:
        return 'Finish · ${s.remaining} reading${s.remaining == 1 ? '' : 's'} left';
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
      'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  /// Opens the schedule/detail for any reading item (personal plan or group).
  void _openPrimarySchedule(_ReadingItem item) {
    if (item.isGroup) {
      final g = _groups[item.group!.id];
      if (g != null) _openGroupSchedule(g);
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

  Future<void> _openReadingPlansHub() async {
    unawaited(widget.vibrationService.lightImpact());
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AllPlansPage(
          firestore: widget.firestore,
          auth: widget.auth,
          groupService: widget.groupService,
          readingPlanService: widget.readingPlanService,
          userPreferencesService: widget.userPreferencesService,
          friendService: widget.friendService,
          vibrationService: widget.vibrationService,
          dateProvider: widget.dateProvider,
        ),
      ),
    );
    // The hub can change the pinned reading; refresh the preference and reload
    // the group so Home re-picks its hero (incl. surfacing a newly pinned group).
    if (mounted) {
      await _loadPreferences();
      if (mounted) await _loadGroup();
    }
  }

  /// The "Start a new plan" affordance, shown wherever the reader might add a
  /// plan — beneath the reading list and in the no-plan state alike.
  Widget _buildStartNewPlanButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () => _startNewPlan(),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Start a new plan'),
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurfaceVariant,
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  /// Asks whether to start a personal or group plan, then routes to the matching
  /// creation flow. A new personal plan flows in through the active-plans stream
  /// on its own; a new group isn't streamed, so the group branch reloads Home so
  /// it can surface as the hero.
  Future<void> _startNewPlan() async {
    unawaited(widget.vibrationService.lightImpact());
    final kind = await showNewPlanPicker(context);
    if (kind == null || !mounted) return;

    switch (kind) {
      case NewPlanKind.personal:
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CreatePlanPage(
            firestore: widget.firestore,
            auth: widget.auth,
            vibrationService: widget.vibrationService,
          ),
        ));
      case NewPlanKind.group:
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CreateGroupPage(
            groupService: widget.groupService,
            auth: widget.auth,
            vibrationService: widget.vibrationService,
          ),
        ));
        if (mounted) {
          await _loadPreferences();
          if (mounted) await _loadGroup();
        }
    }
  }

  String _groupPresenceLabel(List<GroupMemberProgressData> readers) {
    if (readers.isEmpty) return 'Be the first to read this';
    final names = readers.take(2).map((r) => r.name.split(' ').first).toList();
    final more = readers.length - names.length;
    final suffix = more > 0 ? ' & $more other${more > 1 ? 's' : ''}' : '';
    return '${names.join(', ')}$suffix read today';
  }

  void _openGroupSchedule(_GroupData g) {
    unawaited(widget.vibrationService.lightImpact());
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullSchedulePage(
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
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.of(context).border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpenJourney,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _weekDot(
                        context, labels[i], _readOnWeekday(i == 0 ? 7 : i)),
                  ],
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Here $_totalReadDays day${_totalReadDays == 1 ? '' : 's'} this season',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
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
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  /// The bottom "Your community" glimpse: who among the user and their friends
  /// has read today. Tapping opens the Community tab.
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
    } else {
      subtitle = '${firstName(readers[0])}, ${firstName(readers[1])} '
          '& others showed up';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Your community',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton(
                onPressed: widget.onOpenCommunity,
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Open'),
              ),
            ],
          ),
        ),
        Material(
          color: colorScheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.of(context).border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onOpenCommunity,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  MemberPresenceStack(
                    members: readers
                        .map((r) => GroupMemberProgressData(
                              uid: r.uid,
                              name: r.name,
                              completion: 1.0,
                            ))
                        .toList(),
                    size: 36,
                    max: 5,
                    showDoneBadge: false,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${readers.length} of $_communityTotal read today',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
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
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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
    _animationController.dispose();
    _syncSub?.cancel();
    _activePlansSub?.cancel();
    for (final timer in _loadTimers) {
      timer.cancel();
    }
    _loadTimers.clear();
    for (final sub in _loadSubs) {
      sub.cancel();
    }
    _loadSubs.clear();
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

/// An active personal plan paired with the user's progress on it.
class _PersonalPlan {
  final ReadingPlan plan;
  final UserPlanProgress progress;

  const _PersonalPlan({required this.plan, required this.progress});
}

/// A single rankable reading on Home — a personal plan or the user's group —
/// together with its computed catch-up [status] and [PlanLifecycle] state.
class _ReadingItem {
  final bool isGroup;
  final ReadingPlan? plan;
  final UserPlanProgress? progress;
  final Group? group;
  final CatchUpStatus status;
  final PlanLifecycle state;

  _ReadingItem.personal(this.plan, this.progress, this.status, this.state)
      : isGroup = false,
        group = null;

  _ReadingItem.group(this.group, this.status, this.state)
      : isGroup = true,
        plan = null,
        progress = null;

  String get title => isGroup ? group!.name : plan!.title;

  /// Typed pin key matching `UserPreferences.pinnedReadingId`.
  String get pinKey => isGroup ? 'group:${group!.id}' : 'plan:${plan!.id}';
}

/// Per-group state backing the "together" reading cards on Home — one entry per
/// group the user belongs to, holding that group's schedule, today's entry,
/// member presence, the completed-date set used by the catch-up engine, and a
/// per-group mark-loading flag (so marking one group doesn't spin the others).
class _GroupData {
  _GroupData({
    required this.group,
    this.schedule = const [],
    this.today,
    this.members = const [],
    this.completedDateIds = const {},
  });

  final Group group;
  List<GroupSchedule> schedule;
  GroupSchedule? today;
  List<GroupMemberProgressData> members;
  Set<String> completedDateIds;
  bool markLoading = false;
}
