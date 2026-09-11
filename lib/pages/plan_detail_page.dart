import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_member_progress.dart';
import '../models/group_schedule.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';
import '../services/catch_up_engine.dart';
import '../services/group_service.dart';
import '../services/plan_completion_coordinator.dart';
import '../services/read_log_service.dart';
import '../services/reading_plan_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/burst_undo_controller.dart';
import '../widgets/common_styles.dart';
import '../widgets/member_presence_stack.dart';
import '../widgets/schedule_preview.dart';
import '../widgets/schedule_screen_view.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/skeletons/plan_detail_skeleton.dart';

class PlanDetailPage extends StatefulWidget {
  final ReadingPlan? plan;
  final FirebaseFirestore? firestore;
  final FirebaseAuth auth;
  final UserPlanProgress? initialProgress;
  final VibrationService vibrationService;

  // Group schedule mode parameters
  final Group? group;
  final GroupService? groupService;
  final List<GroupSchedule>? initialSchedule;
  final bool isMember;

  const PlanDetailPage({
    super.key,
    this.plan,
    this.firestore,
    required this.auth,
    this.initialProgress,
    this.vibrationService = const VibrationService(),
    this.group,
    this.groupService,
    this.initialSchedule,
    this.isMember = false,
  }) : assert(
          plan != null || (group != null && groupService != null),
          'Either plan or group and groupService must be provided',
        );

  @override
  State<PlanDetailPage> createState() => _PlanDetailPageState();
}

class _PlanDetailPageState extends State<PlanDetailPage> {
  ReadingPlanService? _planServiceInstance;
  ReadingPlanService get _planService => _planServiceInstance ??=
      ReadingPlanService(firestore: _effectiveFirestore);

  PlanCompletionCoordinator? _coordinator;
  PlanCompletionCoordinator get _completionCoordinator =>
      _coordinator ??= PlanCompletionCoordinator(
        firestore: _effectiveFirestore,
        planService: widget.plan != null ? _planService : null,
      );

  FirebaseFirestore get _effectiveFirestore =>
      widget.firestore ??
      widget.groupService?.firestore ??
      FirebaseFirestore.instance;

  // Personal plan streams / state
  late Stream<UserPlanProgress?> _progressStream;
  Set<int>? _optimisticCompletedDays;

  // Group schedule streams / state
  late Stream<List<GroupSchedule>> _groupScheduleStream;
  late Stream<Map<String, int>> _groupProgressStream;
  final Map<String, int> _optimisticGroupProgress = {};

  /// Coalesces rapid marks into one undoable burst (ADR-0005).
  late final BurstUndoController _burstUndo;

  bool get _isGroupMode => widget.group != null;

  @override
  void initState() {
    super.initState();
    _burstUndo = BurstUndoController();
    final user = widget.auth.currentUser;

    if (_isGroupMode) {
      _groupScheduleStream = widget.groupService!.schedule(widget.group!.id);
      if (user != null) {
        _groupProgressStream = widget.groupService!.userProgressForGroup(
          widget.group!.id,
          user.uid,
        );
      } else {
        _groupProgressStream = Stream.value({});
      }
    } else {
      if (user != null) {
        _progressStream =
            _planService.getPlanProgress(user.uid, widget.plan!.id);
      } else {
        _progressStream = Stream.value(null);
      }
    }
  }

  @override
  void dispose() {
    _burstUndo.dispose();
    super.dispose();
  }

  Future<void> _startPlan() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final currentYear = now.year;
    final jan1 = DateTime(currentYear, 1, 1);

    final DateTime? pickedDate = await showModalBottomSheet<DateTime>(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'When would you like to start?',
                  style: AppTextStyles.subtitle(context),
                ),
                const SizedBox(height: 24),
                ListTile(
                  leading: const Icon(Icons.today),
                  title: const Text('Start Today'),
                  subtitle: Text(_formatDate(now)),
                  onTap: () => Navigator.pop(context, now),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                if (jan1.isBefore(now)) ...[
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Start on January 1st'),
                    subtitle: const Text('Catch up or join late'),
                    onTap: () => Navigator.pop(context, jan1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.edit_calendar),
                  title: const Text('Pick a Date'),
                  subtitle: const Text('Choose a custom start date'),
                  onTap: () async {
                    final customDate = await showDatePicker(
                      context: context,
                      initialDate: now,
                      firstDate: DateTime(currentYear - 1),
                      lastDate: DateTime(currentYear + 2),
                    );
                    if (context.mounted && customDate != null) {
                      Navigator.pop(context, customDate);
                    }
                  },
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (pickedDate != null && widget.plan != null) {
      // Re-enrollment collision (#776): the plan was soft-deleted earlier and
      // its old progress still waits in the trash. Ask before clobbering it.
      final collision = await _planService.startPlan(
        user.uid,
        widget.plan!.id,
        startDate: pickedDate,
      );
      if (collision != null && mounted) {
        final restore = await showDialog<bool>(
          context: context,
          barrierColor: AppColors.of(context).scrim,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Restore your progress?'),
            content: Text(
              'You deleted "${widget.plan!.title}" earlier, but its reading '
              'record is still there for a few more days. Restore it and '
              'continue where you left off, or start fresh?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Start Fresh'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Restore Progress'),
              ),
            ],
          ),
        );
        if (restore == true) {
          await _planService.startPlan(
            user.uid,
            widget.plan!.id,
            restoreDeleted: true,
          );
        } else {
          // Start fresh: drop the trashed record, then start anew.
          await _planService.permanentlyDeletePlan(user.uid, widget.plan!.id);
          await _planService.startPlan(
            user.uid,
            widget.plan!.id,
            startDate: pickedDate,
          );
        }
      }
    }
  }

  String _formatDate(DateTime date) {
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
    return '${months[date.month - 1]} ${date.day}';
  }

  String _formatDayOfWeek(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  String _dateId(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Infers cadence from the median gap between consecutive schedule dates.
  String _cadenceLabel(List<GroupSchedule> schedule) {
    if (schedule.length < 2) return 'Today';
    final gaps = <int>[];
    for (var i = 1; i < schedule.length; i++) {
      gaps.add(schedule[i].date.difference(schedule[i - 1].date).inDays.abs());
    }
    gaps.sort();
    final median = gaps[gaps.length ~/ 2];
    return median >= 4 ? 'This week' : 'Today';
  }

  Widget _buildSharedPlanBadge(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final count = widget.group?.memberCount ?? 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              'Shared plan',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count ${count == 1 ? 'reader' : 'readers'} on this schedule',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = _isGroupMode ? widget.group!.name : widget.plan!.title;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface.withValues(alpha: 0.95),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(title, style: theme.textTheme.titleLarge),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
            height: 1,
          ),
        ),
      ),
      body:
          _isGroupMode ? _buildGroupBody(context) : _buildPersonalBody(context),
    );
  }

  Widget _buildGroupBody(BuildContext context) {
    return StreamBuilder<List<GroupSchedule>>(
      stream: _groupScheduleStream,
      initialData: widget.initialSchedule,
      builder: (context, scheduleSnapshot) {
        if (scheduleSnapshot.hasError) {
          return Center(child: Text('Error: ${scheduleSnapshot.error}'));
        }
        if (!scheduleSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final fullSchedule = scheduleSnapshot.data!;
        if (fullSchedule.isEmpty) {
          return const Center(child: Text('No schedule available'));
        }

        fullSchedule.sort((a, b) => a.date.compareTo(b.date));
        final cadenceLabel = _cadenceLabel(fullSchedule);

        return StreamBuilder<Map<String, int>>(
          stream: _groupProgressStream,
          builder: (context, progressSnapshot) {
            final remoteProgress = progressSnapshot.data ?? {};

            if (progressSnapshot.hasData) {
              final toRemove = <String>[];
              _optimisticGroupProgress.forEach((dateId, value) {
                if (remoteProgress[dateId] == value) {
                  toRemove.add(dateId);
                }
              });
              for (final id in toRemove) {
                _optimisticGroupProgress.remove(id);
              }
            }

            final progress = {...remoteProgress, ..._optimisticGroupProgress};

            final completedIds = <String>{};
            for (final s in fullSchedule) {
              final dateId = _dateId(s.date);
              final count = progress[dateId] ?? 0;
              final isRead =
                  s.chapters.isEmpty ? count > 0 : count >= s.chapters.length;
              if (isRead) completedIds.add(dateId);
            }

            final status = CatchUpEngine.forGroupSchedule(
              fullSchedule,
              completedIds,
              today: DateTime.now(),
            );

            return ScheduleScreenView(
              status: status,
              title: widget.group!.name,
              isGroup: true,
              readOnly: !widget.isMember,
              header: _buildSharedPlanBadge(context),
              onMarkMonth: (month) =>
                  _markGroupMonth(month, fullSchedule, completedIds),
              onToggle: (i) {
                final s = fullSchedule[i];
                final isRead = completedIds.contains(_dateId(s.date));
                unawaited(_handleGroupToggle(s, isRead));
              },
              todayAnchorBuilder: (ctx) {
                final s = fullSchedule[status.currentIndex];
                final isRead = completedIds.contains(_dateId(s.date));
                return _TodayAnchorCard(
                  group: widget.group!,
                  groupService: widget.groupService!,
                  schedule: s,
                  isRead: isRead,
                  isMember: widget.isMember,
                  currentUid: widget.auth.currentUser?.uid,
                  cadenceLabel: cadenceLabel,
                  dateLabel:
                      '${_formatDayOfWeek(s.date)} ${_formatDate(s.date)}',
                  onToggle: () => unawaited(_handleGroupToggle(s, isRead)),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPersonalBody(BuildContext context) {
    return StreamBuilder<UserPlanProgress?>(
      stream: _progressStream,
      initialData: widget.initialProgress,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null;
        final streamProgress = snapshot.data;
        final isStarted = streamProgress != null;

        return SkeletonLoader(
          loading: isLoading,
          minTime: const Duration(milliseconds: 1000),
          skeleton: const PlanDetailSkeleton(),
          child: _PlanDetailContent(
            plan: widget.plan!,
            progress: streamProgress,
            isStarted: isStarted,
            optimisticCompletedDays: _optimisticCompletedDays,
            onToggleDay: _toggleDay,
            onStartPlan: _startPlan,
            onMarkMonth: _markMonth,
            formatDate: _formatDate,
            formatDayOfWeek: _formatDayOfWeek,
          ),
        );
      },
    );
  }

  Future<void> _handleGroupToggle(
    GroupSchedule schedule,
    bool isRead, {
    bool coupleHabit = true,
  }) async {
    if (!widget.isMember) return;

    final user = widget.auth.currentUser;
    if (user == null) return;

    final dateId = _dateId(schedule.date);
    final previousOptimistic = _optimisticGroupProgress[dateId];

    unawaited(widget.vibrationService.lightImpact());

    setState(() {
      _optimisticGroupProgress[dateId] =
          !isRead ? (schedule.chapters.length.clamp(1, 999)) : 0;
    });

    final success = await widget.groupService!.toggleReadStatus(
      groupId: widget.group!.id,
      uid: user.uid,
      schedule: schedule,
      read: !isRead,
    );

    if (!mounted) return;
    if (!success) {
      setState(() {
        if (previousOptimistic == null) {
          _optimisticGroupProgress.remove(dateId);
        } else {
          _optimisticGroupProgress[dateId] = previousOptimistic;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update read status')),
      );
      return;
    }

    if (!isRead) {
      if (_burstUndo.count == 0) {
        _burstUndo.habitBeforeBurst = await _isHabitRecordedToday(user);
      }
      if (mounted) {
        _burstUndo.add(context, () {
          _handleGroupToggle(schedule, true);
          if (_burstUndo.couplingFiredInBurst && !_burstUndo.habitBeforeBurst) {
            _burstUndo.couplingFiredInBurst = false;
            final u = widget.auth.currentUser;
            if (u == null) return;
            unawaited(
              ReadLogService(firestore: _effectiveFirestore).clear(
                u,
                date: DateTime.now(),
              ),
            );
          }
        });
      }
      if (!mounted) return;
      if (coupleHabit) {
        final coupled = await _completionCoordinator.maybeCoupleHabit(
          context: context,
          user: user,
          onMessage: _burstUndo.count > 1 ? null : _showSnack,
        );
        if (coupled) _burstUndo.couplingFiredInBurst = true;
      }
    }
  }

  Future<void> _markGroupMonth(
    DateTime month,
    List<GroupSchedule> fullSchedule,
    Set<String> completedIds,
  ) async {
    final user = widget.auth.currentUser;
    if (user == null || !widget.isMember) return;

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    final unreadInMonth = fullSchedule.where((s) {
      final sDate = DateTime(s.date.year, s.date.month, s.date.day);
      return s.date.year == month.year &&
          s.date.month == month.month &&
          !sDate.isAfter(todayDate) &&
          !completedIds.contains(_dateId(s.date));
    }).toList();

    if (unreadInMonth.isEmpty) return;

    for (final schedule in unreadInMonth) {
      await _handleGroupToggle(schedule, false, coupleHabit: false);
    }

    if (!mounted) return;
    final coupled = await _completionCoordinator.maybeCoupleHabit(
      context: context,
      user: user,
    );
    if (coupled) _burstUndo.couplingFiredInBurst = true;
  }

  Future<void> _toggleDay(
    int dayNumber,
    bool wasCompleted,
    Set<int> completedDays, {
    bool coupleHabit = true,
  }) async {
    final user = widget.auth.currentUser;
    if (user == null || widget.plan == null) return;

    unawaited(widget.vibrationService.lightImpact());

    final previousOptimistic = _optimisticCompletedDays != null
        ? Set<int>.from(_optimisticCompletedDays!)
        : (await _planService.getPlanProgress(user.uid, widget.plan!.id).first)
                ?.completedDays
                .toSet() ??
            {};

    final newCompletedDays = Set<int>.from(completedDays);
    if (wasCompleted) {
      newCompletedDays.remove(dayNumber);
    } else {
      newCompletedDays.add(dayNumber);
    }

    setState(() {
      _optimisticCompletedDays = newCompletedDays;
    });

    try {
      if (wasCompleted) {
        await _planService.unmarkDayComplete(
          user.uid,
          widget.plan!.id,
          dayNumber,
        );
      } else {
        await _planService.markDayComplete(
            user.uid, widget.plan!.id, dayNumber);
        // Snapshot today's habit at burst start so a burst undo can revert
        // the habit exactly when the burst caused it (ADR-0005).
        if (_burstUndo.count == 0) {
          _burstUndo.habitBeforeBurst = await _isHabitRecordedToday(user);
        }
        if (!mounted) return;
        _burstUndo.add(context, () => _undoDay(dayNumber, newCompletedDays));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _optimisticCompletedDays = previousOptimistic;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update progress. Please try again.'),
          ),
        );
      }
      return;
    }

    // Coupling is one-directional and opt-in: finishing a plan reading may also
    // count as "showing up" for the day. Un-marking never touches the habit.
    // During a burst (more than one mark) the follow-up message is folded into
    // the burst toast, so it is suppressed here (ADR-0005).
    if (!wasCompleted && mounted && coupleHabit) {
      final coupled = await _completionCoordinator.maybeCoupleHabit(
        context: context,
        user: user,
        onMessage: _burstUndo.count > 1 ? null : _showSnack,
      );
      if (coupled) _burstUndo.couplingFiredInBurst = true;
    }
  }

  /// Whether today's habit ("showing up") is already recorded for [user].
  Future<bool> _isHabitRecordedToday(User user) async {
    final today = DateTime.now();
    final dateKey = ReadLogService.dateKeyFor(today);
    try {
      final doc = await _effectiveFirestore
          .collection('users')
          .doc(user.uid)
          .collection('reading')
          .doc(dateKey)
          .get();
      return doc.exists && doc.data()?['read'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Undoes one mark of a burst: un-marks the day and, when the burst caused
  /// today's habit to be recorded, reverts it (ADR-0005).
  void _undoDay(int dayNumber, Set<int> completedDays) {
    _toggleDay(dayNumber, true, completedDays);
    if (_burstUndo.couplingFiredInBurst && !_burstUndo.habitBeforeBurst) {
      // Revert once per burst; later actions in the same burst skip.
      _burstUndo.couplingFiredInBurst = false;
      final user = widget.auth.currentUser;
      if (user == null) return;
      unawaited(
        ReadLogService(firestore: _effectiveFirestore).clear(
          user,
          date: DateTime.now(),
        ),
      );
    }
  }

  /// Marks every uncompleted day of [month] up to and including today as one
  /// burst (ADR-0005). [days] is the day numbers to mark, computed by the
  /// content (which owns the start date). Couples the habit once, silently.
  Future<void> _markMonth(List<int> days) async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    if (days.isEmpty) return;

    final completed = _optimisticCompletedDays ??
        (await _planService.getPlanProgress(user.uid, widget.plan!.id).first)
            ?.completedDays
            .toSet() ??
        {};

    var running = Set<int>.from(completed);
    for (final day in days) {
      await _toggleDay(day, false, running, coupleHabit: false);
      running = Set<int>.from(running)..add(day);
    }

    // Couple once, silently: the burst toast is the only feedback.
    if (!mounted) return;
    final coupled = await _completionCoordinator.maybeCoupleHabit(
      context: context,
      user: user,
    );
    if (coupled) _burstUndo.couplingFiredInBurst = true;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PlanDetailContent extends StatefulWidget {
  final ReadingPlan plan;
  final UserPlanProgress? progress;
  final bool isStarted;
  final Set<int>? optimisticCompletedDays;
  final Function(int, bool, Set<int>) onToggleDay;
  final VoidCallback onStartPlan;
  final void Function(List<int> days)? onMarkMonth;
  final String Function(DateTime) formatDate;
  final String Function(DateTime) formatDayOfWeek;

  const _PlanDetailContent({
    required this.plan,
    required this.progress,
    required this.isStarted,
    this.optimisticCompletedDays,
    required this.onToggleDay,
    required this.onStartPlan,
    this.onMarkMonth,
    required this.formatDate,
    required this.formatDayOfWeek,
  });

  @override
  State<_PlanDetailContent> createState() => _PlanDetailContentState();
}

class _PlanDetailContentState extends State<_PlanDetailContent> {
  final Map<int, GlobalKey> _itemKeys = {};

  /// In the not-started preview, whether the full schedule list is expanded.
  bool _showFullSchedule = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!widget.isStarted) {
      return _buildNotStartedState(context, colorScheme);
    }

    final completedDays = widget.optimisticCompletedDays ??
        widget.progress?.completedDays.toSet() ??
        {};
    final startDate = widget.progress!.startDate;

    // Drive the shared, design-matched schedule view from the same catch-up
    // engine the group page uses. Apply optimistic completion so toggles feel
    // instant; `ScheduleEntry.index` is the plan day number, so `onToggle`
    // routes straight back to `onToggleDay` (which honors the habit coupling).
    final status = CatchUpEngine.forPersonalPlan(
      widget.plan,
      UserPlanProgress(
        planId: widget.plan.id,
        userId: widget.progress!.userId,
        startDate: startDate,
        completedDays: completedDays.toList(),
      ),
      today: DateTime.now(),
    );

    return ScheduleScreenView(
      status: status,
      title: widget.plan.title,
      isGroup: false,
      onMarkMonth: (month) {
        // Days in [month] up to and including today that are still unmarked
        // (ADR-0005 marks up to today, never ahead). Dates come from the
        // start date, not the day number.
        final today = DateTime.now();
        final days = <int>[];
        for (final day in widget.plan.schedule) {
          final date = startDate.add(Duration(days: day.day - 1));
          if (date.year == month.year &&
              date.month == month.month &&
              !date.isAfter(today) &&
              !completedDays.contains(day.day)) {
            days.add(day.day);
          }
        }
        if (days.isNotEmpty) widget.onMarkMonth?.call(days);
      },
      header: Padding(
        padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
        child: Text(
          widget.plan.description,
          style: AppTextStyles.body(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ),
      onToggle: (i) {
        final entry = status.entries[i];
        widget.onToggleDay(entry.index, entry.completed, completedDays);
      },
    );
  }

  Widget _buildNotStartedState(BuildContext context, ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.plan.description,
                  style: AppTextStyles.body(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.onStartPlan,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start This Plan'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          const SizedBox(height: 8),
          SchedulePreview(
            status: CatchUpEngine.forPersonalPlan(
              widget.plan,
              UserPlanProgress(
                planId: widget.plan.id,
                userId: '',
                startDate: DateTime.now(),
                completedDays: const [],
              ),
              today: DateTime.now(),
            ),
            title: widget.plan.title,
            onViewFull: _showFullSchedule
                ? null
                : () => setState(() => _showFullSchedule = true),
          ),
          if (_showFullSchedule) ...[
            const SizedBox(height: 16),
            _buildSectionHeader(context, 'Full Schedule'),
            ...widget.plan.schedule.map(
              (day) => _buildScheduleItem(
                context,
                day,
                DateTime.now(),
                {},
                isStarted: false,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title, {
    bool isHighlight = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8, top: 8),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color:
              isHighlight ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildScheduleItem(
    BuildContext context,
    ReadingPlanDay day,
    DateTime startDate,
    Set<int> completedDays, {
    bool isPast = false,
    bool isStarted = true,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCompleted = completedDays.contains(day.day);
    final date = startDate.add(Duration(days: day.day - 1));
    final opacity = (isPast || isCompleted) ? 0.7 : 1.0;

    final key = _itemKeys.putIfAbsent(day.day, () => GlobalKey());

    return Opacity(
      key: key,
      opacity: opacity,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isCompleted
              ? colorScheme.surfaceContainerHigh
              : colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: !isStarted
              ? null
              : () => widget.onToggleDay(day.day, isCompleted, completedDays),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.formatDate(date),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        widget.formatDayOfWeek(date),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Day ${day.day}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        day.readings.join(', '),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurface.withValues(alpha: 0.8),
                          decoration:
                              isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCompleted)
                  Icon(Icons.check_circle, color: colorScheme.primary, size: 24)
                else
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorScheme.outline.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "with your group" anchor for the current reading — shows member presence
/// (who has already read it) and a warm "I read this with the group" action.
/// Ports the design's `TodayAnchor` (schedule.jsx) for issue #721.
class _TodayAnchorCard extends StatelessWidget {
  final Group group;
  final GroupService groupService;
  final GroupSchedule schedule;
  final bool isRead;
  final bool isMember;
  final String? currentUid;
  final String cadenceLabel;
  final String dateLabel;
  final VoidCallback onToggle;

  const _TodayAnchorCard({
    required this.group,
    required this.groupService,
    required this.schedule,
    required this.isRead,
    required this.isMember,
    required this.currentUid,
    required this.cadenceLabel,
    required this.dateLabel,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.of(context).primarySoft,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(color: AppColors.of(context).primaryLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$cadenceLabel · with your group',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                dateLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            schedule.chapters.join(', '),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          _buildPresence(context),
          const SizedBox(height: 16),
          if (isMember) _buildAction(context),
        ],
      ),
    );
  }

  Widget _buildPresence(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StreamBuilder<List<GroupMemberProgressData>>(
      stream: groupService.memberDailyCompletion(group.id, date: schedule.date),
      builder: (context, snapshot) {
        final readers = (snapshot.data ?? [])
            .where((m) => m.completion >= 1.0 && m.uid != currentUid)
            .toList();

        final names = readers.take(2).map((r) => r.name.split(' ').first);
        final more = readers.length - names.length;
        final String label;
        if (readers.isEmpty) {
          label = 'Be the first to read this';
        } else {
          final more1 = more > 0 ? ' & $more other${more > 1 ? 's' : ''}' : '';
          label = '${names.join(', ')}$more1 have read';
        }

        return Row(
          children: [
            if (readers.isNotEmpty) ...[
              MemberPresenceStack(
                members: readers,
                size: 26,
                max: 4,
                showDoneBadge: false,
              ),
              const SizedBox(width: 11),
            ],
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAction(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!isRead) {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton.icon(
          onPressed: onToggle,
          icon: const Icon(Icons.check, size: 18),
          label: const Text(
            'I read this with the group',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
    }

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary,
              ),
              child: Icon(Icons.check, size: 17, color: colorScheme.onPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'You read with your group today.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.close, size: 13, color: colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  'Undo',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
