import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/group.dart';
import '../models/group_member_progress.dart';
import '../models/group_schedule.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';
import 'catch_up_engine.dart';
import 'error_logger.dart';
import 'group_service.dart';
import 'plan_pace_service.dart';
import 'reading_plan_service.dart';
import 'user_preferences_service.dart';

/// A fully resolved, lifecycle-evaluated active reading item for a reader —
/// either a solo personal plan ([ActivePersonalReading]) or a shared group
/// schedule ([ActiveGroupReading]).
abstract class ActiveReadingItem {
  const ActiveReadingItem();

  String get id;
  String get title;
  String get pinKey;
  CatchUpStatus get status;
  PlanLifecycle get state;
  bool get finished;
  bool get isGroup;

  /// Whether this reading has finished early (ADR-0010) or completed all readings.
  /// Finished or completed readings leave Home and collapse into Path's Finished list.
  bool get isDone => state == PlanLifecycle.complete || finished;

  /// Number of readings behind schedule.
  int get missedCount => status.missedCount;

  /// Total readings in this plan or group schedule.
  int get totalReadings => status.total;

  /// Total readings marked complete by this reader.
  int get doneCount => status.doneCount;

  /// Solo reading plan details, or `null` if this is a group schedule.
  ReadingPlan? get plan;

  /// Solo plan progress, or `null` if this is a group schedule.
  UserPlanProgress? get progress;

  /// Group details, or `null` if this is a solo personal plan.
  Group? get group;

  /// Schedule entries for a group schedule, or empty list for solo plans.
  List<GroupSchedule> get schedule => const [];

  /// Today's schedule entry, or `null` if not applicable or rest day.
  GroupSchedule? get todaySchedule => null;

  /// Member presence and completions for today, or empty list for solo plans.
  List<GroupMemberProgressData> get members => const [];

  /// The reader's completed dates under schedule (`YYYY-MM-DD`).
  Set<String> get completedDateIds => const {};

  /// Whether the reader follows their own pace overlay (ADR-0007).
  bool get ownPace => false;
}

/// A solo personal plan paired with the reader's progress, lifecycle state,
/// and computed catch-up status.
class ActivePersonalReading extends ActiveReadingItem {
  @override
  final ReadingPlan plan;

  @override
  final UserPlanProgress progress;

  @override
  final CatchUpStatus status;

  @override
  final PlanLifecycle state;

  @override
  final bool finished;

  const ActivePersonalReading({
    required this.plan,
    required this.progress,
    required this.status,
    required this.state,
    this.finished = false,
  });

  @override
  String get id => plan.id;

  @override
  String get title => plan.title;

  @override
  String get pinKey => 'plan:${plan.id}';

  @override
  bool get isGroup => false;

  @override
  bool get isDone => state == PlanLifecycle.complete || finished;

  @override
  int get missedCount => status.missedCount;

  @override
  int get totalReadings => status.total;

  @override
  int get doneCount => status.doneCount;

  @override
  Group? get group => null;

  /// The current due/missed reading day index (1-based), if one exists.
  int? get currentDay => status.currentEntry?.index;

  /// Whether the reader has marked the current reading day complete.
  bool get isCurrentDayCompleted =>
      currentDay != null && progress.completedDays.contains(currentDay);

  ActivePersonalReading copyWith({
    ReadingPlan? plan,
    UserPlanProgress? progress,
    CatchUpStatus? status,
    PlanLifecycle? state,
    bool? finished,
  }) {
    return ActivePersonalReading(
      plan: plan ?? this.plan,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      state: state ?? this.state,
      finished: finished ?? this.finished,
    );
  }

  ActivePersonalReading withFinished(bool finished) =>
      copyWith(finished: finished);
}

/// A shared group schedule paired with the group metadata, member presence,
/// the reader's personal pace overlay (if any), and computed catch-up status.
class ActiveGroupReading extends ActiveReadingItem {
  @override
  final Group group;

  @override
  final List<GroupSchedule> schedule;

  /// Today's schedule entry, or `null` if nothing is scheduled today (e.g. rest day).
  @override
  final GroupSchedule? todaySchedule;

  /// Member presence and completions for today.
  @override
  final List<GroupMemberProgressData> members;

  /// The reader's completed dates under [schedule] (`YYYY-MM-DD`).
  @override
  final Set<String> completedDateIds;

  @override
  final CatchUpStatus status;

  @override
  final PlanLifecycle state;

  @override
  final bool finished;

  /// Whether the reader follows their own pace overlay instead of the Group's schedule (ADR-0007).
  @override
  final bool ownPace;

  const ActiveGroupReading({
    required this.group,
    this.schedule = const [],
    this.todaySchedule,
    this.members = const [],
    this.completedDateIds = const {},
    required this.status,
    required this.state,
    this.finished = false,
    this.ownPace = false,
  });

  @override
  String get id => group.id;

  @override
  String get title => group.name;

  @override
  String get pinKey => 'group:${group.id}';

  @override
  bool get isGroup => true;

  @override
  bool get isDone => state == PlanLifecycle.complete || finished;

  @override
  int get missedCount => status.missedCount;

  @override
  int get totalReadings => status.total;

  @override
  int get doneCount => status.doneCount;

  @override
  ReadingPlan? get plan => null;

  @override
  UserPlanProgress? get progress => null;

  /// Members who have completed today's reading.
  List<GroupMemberProgressData> get readers =>
      members.where((m) => m.completion >= 1.0).toList();

  /// Whether [uid] has marked today's reading complete.
  bool isReadBy(String uid) {
    for (final m in members) {
      if (m.uid == uid) return m.completion >= 1.0;
    }
    return false;
  }

  ActiveGroupReading copyWith({
    Group? group,
    List<GroupSchedule>? schedule,
    GroupSchedule? todaySchedule,
    List<GroupMemberProgressData>? members,
    Set<String>? completedDateIds,
    CatchUpStatus? status,
    PlanLifecycle? state,
    bool? finished,
    bool? ownPace,
  }) {
    return ActiveGroupReading(
      group: group ?? this.group,
      schedule: schedule ?? this.schedule,
      todaySchedule: todaySchedule ?? this.todaySchedule,
      members: members ?? this.members,
      completedDateIds: completedDateIds ?? this.completedDateIds,
      status: status ?? this.status,
      state: state ?? this.state,
      finished: finished ?? this.finished,
      ownPace: ownPace ?? this.ownPace,
    );
  }

  ActiveGroupReading withFinished(bool finished) =>
      copyWith(finished: finished);
}

/// Snapshot of all active and finished readings for a reader at a point in time.
class ActiveReadingsSnapshot {
  final List<ActivePersonalReading> personalPlans;
  final List<ActiveGroupReading> groupReadings;
  final String? pinnedReadingId;

  const ActiveReadingsSnapshot({
    required this.personalPlans,
    required this.groupReadings,
    this.pinnedReadingId,
  });

  static const empty = ActiveReadingsSnapshot(
    personalPlans: [],
    groupReadings: [],
  );

  /// All readings (both personal plans and group schedules).
  List<ActiveReadingItem> get allReadings => [
        ...personalPlans,
        ...groupReadings,
      ];

  /// Ranked reading items for Home (epic #716, #722/#723):
  /// - Excludes content-complete and finished readings (ADR-0010)
  /// - Sorted by lifecycle priority:
  ///   due (0) -> behind (1) -> ontrack (2) -> wrapup (3)
  /// - Ties broken by [missedCount] descending
  /// - Pinned reading (if set) is hoisted to index 0 as hero
  List<ActiveReadingItem> get homeReadings {
    final items = allReadings.where((it) => !it.isDone).toList();
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

    final pinned = pinnedReadingId;
    if (pinned != null) {
      final idx = items.indexWhere((it) => it.pinKey == pinned);
      if (idx > 0) {
        final hero = items.removeAt(idx);
        items.insert(0, hero);
      }
    }
    return items;
  }

  /// Active (non-finished, non-complete) solo plans for "On your own" in PlansHub.
  List<ActivePersonalReading> get activePersonalPlans =>
      personalPlans.where((p) => !p.isDone).toList();

  /// Finished / complete solo plans for "Finished" in PlansHub.
  List<ActivePersonalReading> get finishedPersonalPlans =>
      personalPlans.where((p) => p.isDone).toList();

  /// Active (non-finished, non-complete) group schedules for "Together" in PlansHub.
  List<ActiveGroupReading> get activeGroupReadings =>
      groupReadings.where((g) => !g.isDone).toList();

  /// Finished / complete group schedules for "Finished" in PlansHub.
  List<ActiveGroupReading> get finishedGroupReadings =>
      groupReadings.where((g) => g.isDone).toList();

  /// Total number of active reading items.
  int get activeCount =>
      activePersonalPlans.length + activeGroupReadings.length;

  /// Whether there are any finished/complete items.
  bool get hasFinished =>
      finishedPersonalPlans.isNotEmpty || finishedGroupReadings.isNotEmpty;

  /// Whether the reader has no readings at all (empty state).
  bool get isEmpty => allReadings.isEmpty;

  // Optimistic mutation helpers:

  /// Optimistically updates a personal plan's progress and recomputes status/lifecycle.
  ActiveReadingsSnapshot withOptimisticPlanProgress(
    String planId,
    UserPlanProgress nextProgress, {
    DateTime? today,
  }) {
    final now = today ?? DateTime.now();
    final updated = personalPlans.map((p) {
      if (p.plan.id != planId) return p;
      final status = CatchUpEngine.forPersonalPlan(
        p.plan,
        nextProgress,
        today: now,
      );
      return ActivePersonalReading(
        plan: p.plan,
        progress: nextProgress,
        status: status,
        state: status.lifecycleAt(now),
        finished: nextProgress.finishedAt != null,
      );
    }).toList();

    return ActiveReadingsSnapshot(
      personalPlans: updated,
      groupReadings: groupReadings,
      pinnedReadingId: pinnedReadingId,
    );
  }

  /// Optimistically updates a group member's completion.
  ActiveReadingsSnapshot withOptimisticGroupCompletion(
    String groupId,
    String uid,
    double completion,
  ) {
    final updated = groupReadings.map((g) {
      if (g.group.id != groupId) return g;
      final hasMember = g.members.any((m) => m.uid == uid);
      final List<GroupMemberProgressData> updatedMembers;
      if (hasMember) {
        updatedMembers = g.members.map((m) {
          if (m.uid != uid) return m;
          return GroupMemberProgressData(
            uid: m.uid,
            name: m.name,
            photoUrl: m.photoUrl,
            completion: completion,
          );
        }).toList();
      } else {
        updatedMembers = [
          ...g.members,
          GroupMemberProgressData(
            uid: uid,
            name: '',
            photoUrl: null,
            completion: completion,
          ),
        ];
      }
      return g.copyWith(members: updatedMembers);
    }).toList();

    return ActiveReadingsSnapshot(
      personalPlans: personalPlans,
      groupReadings: updated,
      pinnedReadingId: pinnedReadingId,
    );
  }

  /// Optimistically marks a solo plan finished or unfinished.
  ActiveReadingsSnapshot withPersonalFinished(String planId, bool finished) {
    final updated = personalPlans.map((p) {
      if (p.plan.id != planId) return p;
      return p.withFinished(finished);
    }).toList();
    return ActiveReadingsSnapshot(
      personalPlans: updated,
      groupReadings: groupReadings,
      pinnedReadingId: pinnedReadingId,
    );
  }

  /// Optimistically marks a group reading finished or unfinished.
  ActiveReadingsSnapshot withGroupFinished(String groupId, bool finished) {
    final updated = groupReadings.map((g) {
      if (g.group.id != groupId) return g;
      return g.withFinished(finished);
    }).toList();
    return ActiveReadingsSnapshot(
      personalPlans: personalPlans,
      groupReadings: updated,
      pinnedReadingId: pinnedReadingId,
    );
  }

  /// Optimistically removes a reading by plan or group ID (e.g. when finishing on Home).
  ActiveReadingsSnapshot withoutReading(String id) {
    return ActiveReadingsSnapshot(
      personalPlans: personalPlans.where((p) => p.id != id).toList(),
      groupReadings: groupReadings.where((g) => g.id != id).toList(),
      pinnedReadingId: pinnedReadingId,
    );
  }

  ActiveReadingsSnapshot withPinnedReadingId(String? pinnedReadingId) {
    return ActiveReadingsSnapshot(
      personalPlans: personalPlans,
      groupReadings: groupReadings,
      pinnedReadingId: pinnedReadingId,
    );
  }
}

/// A deep module consolidating active reading aggregation across solo personal
/// plans and shared group schedules.
///
/// Encapsulates:
/// - Parallel batch loading and in-memory caching of plan documents (eliminating N+1 queries)
/// - Cross-stream coordination between Firestore plan progress, group memberships, schedules,
///   member daily completions, and personal pace overlays (ADR-0007)
/// - Catch-up lifecycle evaluation ([CatchUpEngine]) and ranking for Home
/// - Finished plan filtering and grouping (ADR-0010)
class ActiveReadingAggregator {
  final ReadingPlanService readingPlanService;
  final GroupService groupService;
  final PlanPaceService paceService;
  final UserPreferencesService? userPreferencesService;
  final DateTime Function() dateProvider;

  /// In-memory cache of plan definitions to eliminate N+1 round-trips.
  final Map<String, ReadingPlan> _planCache = {};

  ActiveReadingAggregator({
    required this.readingPlanService,
    required this.groupService,
    PlanPaceService? paceService,
    this.userPreferencesService,
    DateTime Function()? dateProvider,
    FirebaseFirestore? firestore,
  })  : paceService = paceService ??
            PlanPaceService(
              firestore: firestore ?? FirebaseFirestore.instance,
            ),
        dateProvider = dateProvider ?? DateTime.now;

  /// Retrieves a plan by ID, using the in-memory cache when available.
  Future<ReadingPlan?> getPlan(
    String planId, {
    String? userId,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _planCache.containsKey(planId)) {
      return _planCache[planId];
    }
    final plan = await readingPlanService.getPlanById(planId, userId: userId);
    if (plan != null) {
      _planCache[planId] = plan;
    }
    return plan;
  }

  /// Invalidates plan cache entries.
  void invalidateCache({String? planId}) {
    if (planId != null) {
      _planCache.remove(planId);
    } else {
      _planCache.clear();
    }
  }

  /// Batch-loads plan definitions for multiple progresses in parallel,
  /// avoiding sequential N+1 queries.
  Future<Map<String, ReadingPlan>> _batchGetPlans(
    Iterable<String> planIds, {
    String? userId,
    bool forceRefresh = false,
  }) async {
    final result = <String, ReadingPlan>{};
    final missing = <String>[];

    for (final id in planIds) {
      if (!forceRefresh && _planCache.containsKey(id)) {
        result[id] = _planCache[id]!;
      } else {
        missing.add(id);
      }
    }

    if (missing.isNotEmpty) {
      final fetched = await Future.wait(
        missing.map((id) => readingPlanService.getPlanById(id, userId: userId)),
      );
      for (int i = 0; i < missing.length; i++) {
        final plan = fetched[i];
        if (plan != null) {
          _planCache[missing[i]] = plan;
          result[missing[i]] = plan;
        }
      }
    }

    return result;
  }

  /// Resolves any list of [UserPlanProgress] (active or archived) into
  /// fully evaluated [ActivePersonalReading] items using cached batch plan loading.
  Future<List<ActivePersonalReading>> resolvePersonalPlans(
    List<UserPlanProgress> progresses, {
    String? userId,
    DateTime? today,
    bool forceRefresh = false,
  }) async {
    if (progresses.isEmpty) return const [];
    final now = today ?? dateProvider();
    final planIds = progresses.map((p) => p.planId).toSet();
    final plans = await _batchGetPlans(
      planIds,
      userId: userId,
      forceRefresh: forceRefresh,
    );

    final result = <ActivePersonalReading>[];
    for (final progress in progresses) {
      final plan = plans[progress.planId];
      if (plan == null) continue;
      final status = CatchUpEngine.forPersonalPlan(
        plan,
        progress,
        today: now,
      );
      result.add(
        ActivePersonalReading(
          plan: plan,
          progress: progress,
          status: status,
          state: status.lifecycleAt(now),
          finished: progress.finishedAt != null,
        ),
      );
    }
    return result;
  }

  /// Convenience helper to fetch and resolve archived personal plans.
  Future<List<ActivePersonalReading>> fetchArchivedPlans(
    String uid, {
    DateTime? today,
  }) async {
    try {
      final archivedProgress = await _firstWithTimeout<List<UserPlanProgress>>(
        readingPlanService.getArchivedPlans(uid),
        timeout: const Duration(seconds: 5),
        fallback: const [],
      );
      return await resolvePersonalPlans(
        archivedProgress,
        userId: uid,
        today: today,
      );
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      return const [];
    }
  }

  /// Loads all groups for user, their schedules, member completions,
  /// pace overlays, and evaluates lifecycle states concurrently.
  Future<List<ActiveGroupReading>> resolveGroupReadings(
    String uid, {
    DateTime? today,
  }) async {
    try {
      final groups = await _firstWithTimeout<List<Group>>(
        groupService.groupsForUser(uid, includeFinished: true),
        timeout: const Duration(seconds: 5),
        fallback: const [],
      );
      if (groups.isEmpty) return const [];

      final now = today ?? dateProvider();
      final todayDate = DateTime(now.year, now.month, now.day);

      Set<String> finishedGroupIds = const {};
      try {
        finishedGroupIds = await groupService.finishedGroupIdsForUser(uid);
      } catch (e, st) {
        await ErrorLogger.log(e, st);
      }

      final items = await Future.wait(
        groups.map((group) async {
          final results = await Future.wait([
            _firstWithTimeout<List<GroupSchedule>>(
              groupService.schedule(group.id),
              timeout: const Duration(seconds: 3),
              fallback: const [],
            ),
            _firstWithTimeout<List<GroupMemberProgressData>>(
              groupService.memberDailyCompletion(
                group.id,
                date: now,
                includeUid: uid,
              ),
              timeout: const Duration(seconds: 3),
              fallback: const [],
            ),
            _firstWithTimeout<Map<String, int>>(
              groupService.userProgressForGroup(group.id, uid),
              timeout: const Duration(seconds: 3),
              fallback: const {},
            ),
            paceService.getSharedPlanOverlay(uid, group.id).timeout(
                  const Duration(seconds: 3),
                  onTimeout: () => null,
                ),
          ]);

          final overlay = results[3] as List<GroupSchedule>?;
          final schedule = overlay ?? results[0] as List<GroupSchedule>;
          var members = results[1] as List<GroupMemberProgressData>;
          final progress = results[2] as Map<String, int>;

          final completedDateIds = progress.entries
              .where((e) => e.value > 0)
              .map((e) => e.key)
              .toSet();

          final status = CatchUpEngine.forGroupSchedule(
            schedule,
            completedDateIds,
            today: now,
          );

          GroupSchedule? todayEntry;
          for (final s in schedule) {
            if (DateTime(s.date.year, s.date.month, s.date.day) == todayDate) {
              todayEntry = s;
              break;
            }
          }

          if (overlay != null) {
            final todayCount = progress[GroupService.dateId(todayDate)] ?? 0;
            final readToday = todayEntry != null &&
                todayCount > 0 &&
                todayCount >= todayEntry.chapters.length;
            members = [
              for (final m in members)
                m.uid == uid
                    ? GroupMemberProgressData(
                        uid: m.uid,
                        name: m.name,
                        photoUrl: m.photoUrl,
                        completion: readToday ? 1.0 : 0.0,
                      )
                    : m,
            ];
          }

          return ActiveGroupReading(
            group: group,
            schedule: schedule,
            todaySchedule: todayEntry,
            members: members,
            completedDateIds: completedDateIds,
            status: status,
            state: status.lifecycleAt(now),
            finished: finishedGroupIds.contains(group.id),
            ownPace: overlay != null,
          );
        }),
      );

      return items;
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      return const [];
    }
  }

  /// Fetches a complete, lifecycle-evaluated snapshot of active and finished readings.
  Future<ActiveReadingsSnapshot> fetch(
    String uid, {
    DateTime? today,
    String? pinnedReadingId,
    bool forceRefresh = false,
  }) async {
    final now = today ?? dateProvider();

    String? pin = pinnedReadingId;
    if (pin == null && userPreferencesService != null) {
      try {
        final prefs = await userPreferencesService!.fetchPreferences(uid);
        pin = prefs.pinnedReadingId;
      } catch (e, st) {
        await ErrorLogger.log(e, st);
      }
    }

    final personalFuture = _fetchPersonalPlans(
      uid,
      today: now,
      forceRefresh: forceRefresh,
    );
    final groupFuture = resolveGroupReadings(uid, today: now);

    final results = await Future.wait([personalFuture, groupFuture]);
    final personal = results[0] as List<ActivePersonalReading>;
    final groups = results[1] as List<ActiveGroupReading>;

    return ActiveReadingsSnapshot(
      personalPlans: personal,
      groupReadings: groups,
      pinnedReadingId: pin,
    );
  }

  Future<List<ActivePersonalReading>> _fetchPersonalPlans(
    String uid, {
    required DateTime today,
    bool forceRefresh = false,
  }) async {
    try {
      final progresses = await _firstWithTimeout<List<UserPlanProgress>>(
        readingPlanService.getActivePlans(uid),
        timeout: const Duration(seconds: 5),
        fallback: const [],
      );
      return await resolvePersonalPlans(
        progresses,
        userId: uid,
        today: today,
        forceRefresh: forceRefresh,
      );
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      return const [];
    }
  }

  /// Streams live [ActiveReadingsSnapshot] updates whenever personal plans,
  /// groups, schedules, progress, or member presences change.
  Stream<ActiveReadingsSnapshot> watch(
    String uid, {
    DateTime Function()? dateProvider,
    String? pinnedReadingId,
  }) {
    final dates = dateProvider ?? this.dateProvider;
    return Stream<ActiveReadingsSnapshot>.multi((controller) {
      final subs = <StreamSubscription<dynamic>>[];
      final groupSubs = <StreamSubscription<dynamic>>[];
      Timer? debounceTimer;
      bool inFlight = false;
      bool rerunQueued = false;
      String? currentPinned = pinnedReadingId;
      bool closed = false;

      late final void Function() scheduleEmit;

      Future<void> emitLatest() async {
        if (closed || controller.isClosed) return;
        if (inFlight) {
          rerunQueued = true;
          return;
        }
        inFlight = true;
        try {
          final snapshot = await fetch(
            uid,
            today: dates(),
            pinnedReadingId: currentPinned,
          );
          if (!closed && !controller.isClosed) {
            controller.add(snapshot);
          }
        } catch (e, st) {
          if (!closed && !controller.isClosed) {
            controller.addError(e, st);
          }
        } finally {
          inFlight = false;
          if (rerunQueued && !closed && !controller.isClosed) {
            rerunQueued = false;
            scheduleEmit();
          }
        }
      }

      scheduleEmit = () {
        if (closed || controller.isClosed) return;
        debounceTimer?.cancel();
        debounceTimer = Timer(const Duration(milliseconds: 200), () {
          unawaited(emitLatest());
        });
      };

      // Initial emit
      unawaited(emitLatest());

      // Watch personal plan progress
      subs.add(
        readingPlanService.getActivePlans(uid).listen(
              (_) => scheduleEmit(),
              onError: (e) => scheduleEmit(),
            ),
      );

      // Watch groups and sub-resources
      subs.add(
        groupService.groupsForUser(uid, includeFinished: true).listen(
          (groups) {
            for (final s in groupSubs) {
              s.cancel();
            }
            groupSubs.clear();

            for (final g in groups) {
              groupSubs.add(groupService
                  .schedule(g.id)
                  .listen((_) => scheduleEmit(), onError: (_) {}));
              groupSubs.add(groupService
                  .userProgressForGroup(g.id, uid)
                  .listen((_) => scheduleEmit(), onError: (_) {}));
              groupSubs.add(groupService
                  .memberDailyCompletion(g.id, date: dates(), includeUid: uid)
                  .listen((_) => scheduleEmit(), onError: (_) {}));
              groupSubs.add(paceService
                  .sharedPlanOverlay(uid, g.id)
                  .listen((_) => scheduleEmit(), onError: (_) {}));
            }
            scheduleEmit();
          },
          onError: (e) => scheduleEmit(),
        ),
      );

      // Watch user preferences if provided
      if (userPreferencesService != null) {
        subs.add(
          userPreferencesService!.streamPreferences(uid).listen(
            (prefs) {
              if (currentPinned != prefs.pinnedReadingId) {
                currentPinned = prefs.pinnedReadingId;
                scheduleEmit();
              }
            },
            onError: (_) {},
          ),
        );
      }

      controller.onCancel = () {
        closed = true;
        debounceTimer?.cancel();
        for (final s in subs) {
          s.cancel();
        }
        for (final s in groupSubs) {
          s.cancel();
        }
        subs.clear();
        groupSubs.clear();
      };
    });
  }

  /// Safely resolves the first item of [stream], cancelling the timer on completion.
  static Future<T> _firstWithTimeout<T>(
    Stream<T> stream, {
    required Duration timeout,
    required T fallback,
  }) {
    final completer = Completer<T>();
    StreamSubscription<T>? sub;
    Timer? timer;

    void finish(T value) {
      if (completer.isCompleted) return;
      timer?.cancel();
      sub?.cancel();
      completer.complete(value);
    }

    timer = Timer(timeout, () => finish(fallback));
    sub = stream.listen(
      finish,
      onError: (_) => finish(fallback),
      onDone: () => finish(fallback),
    );
    return completer.future;
  }
}
