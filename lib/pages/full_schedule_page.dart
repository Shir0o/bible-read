import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

import '../models/group.dart';
import '../models/group_member_progress.dart';
import '../models/group_schedule.dart';
import '../services/catch_up_engine.dart';
import '../services/group_service.dart';
import '../services/plan_completion_coordinator.dart';
import '../services/vibration_service.dart';
import '../widgets/member_presence_stack.dart';
import '../widgets/schedule_screen_view.dart';

class FullSchedulePage extends StatefulWidget {
  final Group group;
  final GroupService groupService;
  final FirebaseAuth auth;
  final VibrationService vibrationService;
  final List<GroupSchedule>? initialSchedule;
  final bool isMember;

  const FullSchedulePage({
    super.key,
    required this.group,
    required this.groupService,
    required this.auth,
    required this.vibrationService,
    this.initialSchedule,
    this.isMember = false,
  });

  @override
  State<FullSchedulePage> createState() => _FullSchedulePageState();
}

class _FullSchedulePageState extends State<FullSchedulePage> {
  late Stream<List<GroupSchedule>> _scheduleStream;
  late Stream<Map<String, int>> _progressStream;
  final Map<String, int> _optimisticProgress = {};

  /// Built lazily on first read-mark so the page never touches Firebase just to
  /// render (keeps it constructible in tests that only inject a GroupService).
  PlanCompletionCoordinator? _coordinator;
  PlanCompletionCoordinator get _completionCoordinator => _coordinator ??=
      PlanCompletionCoordinator(firestore: FirebaseFirestore.instance);

  @override
  void initState() {
    super.initState();
    _scheduleStream = widget.groupService.schedule(widget.group.id);
    final user = widget.auth.currentUser;
    if (user != null) {
      _progressStream = widget.groupService.userProgressForGroup(
        widget.group.id,
        user.uid,
      );
    } else {
      _progressStream = Stream.value({});
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
    // DateTime.weekday is 1-based (Monday = 1)
    return days[date.weekday - 1];
  }

  String _dateId(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _handleToggle(GroupSchedule schedule, bool isRead) async {
    if (!widget.isMember) return;

    final user = widget.auth.currentUser;
    if (user == null) return;

    final dateId = _dateId(schedule.date);
    final previousOptimistic = _optimisticProgress[dateId];

    unawaited(widget.vibrationService.lightImpact());

    setState(() {
      _optimisticProgress[dateId] =
          !isRead ? (schedule.chapters.length.clamp(1, 999)) : 0;
    });

    final success = await widget.groupService.toggleReadStatus(
      groupId: widget.group.id,
      uid: user.uid,
      schedule: schedule,
      read: !isRead,
    );

    if (!mounted) return;
    if (!success) {
      setState(() {
        if (previousOptimistic == null) {
          _optimisticProgress.remove(dateId);
        } else {
          _optimisticProgress[dateId] = previousOptimistic;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update read status')),
      );
      return;
    }

    // Marking any reading read here — today's or a catch-up day — counts as
    // showing up, so honor the one-directional reading→habit coupling (asks
    // once via SyncSheet, then respects the saved setting). Un-marking never
    // touches the habit. Mirrors the design's `afterReadingMarked` (chat20).
    if (!isRead) {
      await _completionCoordinator.maybeCoupleHabit(
        context: context,
        user: user,
        onMessage: _showSnack,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Group reading marked as complete.'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => _handleToggle(schedule, true),
            ),
          ),
        );
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
        title: Text('Full Schedule', style: theme.textTheme.titleLarge),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
            height: 1,
          ),
        ),
      ),
      body: StreamBuilder<List<GroupSchedule>>(
        stream: _scheduleStream,
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

          // Sort schedule just in case
          fullSchedule.sort((a, b) => a.date.compareTo(b.date));

          // Cadence-aware label for the current reading anchor: weekly group
          // plans read "This week", daily plans read "Today" (issue #721).
          final cadenceLabel = _cadenceLabel(fullSchedule);

          return StreamBuilder<Map<String, int>>(
            stream: _progressStream,
            builder: (context, progressSnapshot) {
              final remoteProgress = progressSnapshot.data ?? {};

              // Clear optimistic overrides if they match remote data
              if (progressSnapshot.hasData) {
                final toRemove = <String>[];
                _optimisticProgress.forEach((dateId, value) {
                  if (remoteProgress[dateId] == value) {
                    toRemove.add(dateId);
                  }
                });
                for (final id in toRemove) {
                  _optimisticProgress.remove(id);
                }
              }

              final progress = {...remoteProgress, ..._optimisticProgress};

              // Date-ids the user has read (whole reading complete), feeding the
              // shared catch-up engine. `fullSchedule` and the engine both sort
              // ascending by date, so entry indices line up one-to-one.
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
                title: widget.group.name,
                isGroup: true,
                readOnly: !widget.isMember,
                onToggle: (i) {
                  final s = fullSchedule[i];
                  final isRead = completedIds.contains(_dateId(s.date));
                  unawaited(_handleToggle(s, isRead));
                },
                todayAnchorBuilder: (ctx) {
                  final s = fullSchedule[status.currentIndex];
                  final isRead = completedIds.contains(_dateId(s.date));
                  return _TodayAnchorCard(
                    group: widget.group,
                    groupService: widget.groupService,
                    schedule: s,
                    isRead: isRead,
                    isMember: widget.isMember,
                    currentUid: widget.auth.currentUser?.uid,
                    cadenceLabel: cadenceLabel,
                    dateLabel:
                        '${_formatDayOfWeek(s.date)} ${_formatDate(s.date)}',
                    onToggle: () => unawaited(_handleToggle(s, isRead)),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  /// Infers cadence from the median gap between consecutive schedule dates.
  /// A gap of ~7 days means a weekly group plan ("This week"); otherwise the
  /// current reading is labelled "Today".
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
        border: Border.all(
          color: AppColors.of(context).primaryLine,
        ),
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
              child: Icon(
                Icons.check,
                size: 17,
                color: colorScheme.onPrimary,
              ),
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
