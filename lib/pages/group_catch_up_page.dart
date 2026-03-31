import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_schedule.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';

class GroupCatchUpPage extends StatefulWidget {
  final Group group;
  final GroupService groupService;
  final FirebaseAuth auth;
  final VibrationService vibrationService;

  const GroupCatchUpPage({
    super.key,
    required this.group,
    required this.groupService,
    required this.auth,
    required this.vibrationService,
  });

  @override
  State<GroupCatchUpPage> createState() => _GroupCatchUpPageState();
}

class _GroupCatchUpPageState extends State<GroupCatchUpPage> {
  late Stream<List<GroupSchedule>> _scheduleStream;
  late Stream<Map<String, int>> _progressStream;
  final Map<String, int> _optimisticProgress = {};

  @override
  void initState() {
    super.initState();
    _scheduleStream = widget.groupService.schedule(widget.group.id);
    final user = widget.auth.currentUser;
    if (user != null) {
      _progressStream =
          widget.groupService.userProgressForGroup(widget.group.id, user.uid);
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
      'Dec'
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

  Future<void> _handleToggle(GroupSchedule schedule, bool isRead) async {
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
    }
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
        title: const Text('Catch Up'),
      ),
      body: StreamBuilder<List<GroupSchedule>>(
        stream: _scheduleStream,
        builder: (context, scheduleSnapshot) {
          if (!scheduleSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final now = DateTime.now();
          final todayDate = DateTime(now.year, now.month, now.day);
          final pastSchedule = scheduleSnapshot.data!
              .where((s) =>
                  DateTime(s.date.year, s.date.month, s.date.day)
                      .isBefore(todayDate))
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date)); // Newest first

          if (pastSchedule.isEmpty) {
            return const Center(child: Text('No past readings to catch up on'));
          }

          return StreamBuilder<Map<String, int>>(
            stream: _progressStream,
            builder: (context, progressSnapshot) {
              final remoteProgress = progressSnapshot.data ?? {};

              if (progressSnapshot.hasData) {
                final toRemove = <String>[];
                _optimisticProgress.forEach((dateId, count) {
                  if (remoteProgress[dateId] == count) {
                    toRemove.add(dateId);
                  }
                });
                for (final id in toRemove) {
                  _optimisticProgress.remove(id);
                }
              }

              final progress = {...remoteProgress, ..._optimisticProgress};

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: pastSchedule.length,
                itemBuilder: (context, index) {
                  final s = pastSchedule[index];
                  final dateId = _dateId(s.date);
                  final count = progress[dateId] ?? 0;
                  final isRead = s.chapters.isEmpty
                      ? count > 0
                      : count >= s.chapters.length;

                  return _buildCatchUpItem(context, s, isRead);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCatchUpItem(
      BuildContext context, GroupSchedule schedule, bool isRead) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _handleToggle(schedule, isRead),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isRead
                  ? colorScheme.primary.withValues(alpha: 0.3)
                  : colorScheme.outline.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDate(schedule.date),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _formatDayOfWeek(schedule.date),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  schedule.chapters.join(', '),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                isRead ? Icons.check_circle : Icons.circle_outlined,
                color: isRead ? colorScheme.primary : colorScheme.outline,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
