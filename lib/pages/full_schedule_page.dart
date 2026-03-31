import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_schedule.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';

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
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _todayKey = GlobalKey();
  bool _hasScrolledToToday = false;
  bool _isScrollPending = false;

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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _scrollToToday() async {
    if (_hasScrolledToToday) return;

    // Give the ListView and page transition a moment to settle
    await Future.delayed(const Duration(milliseconds: 400));

    if (!mounted) return;

    final targetContext = _todayKey.currentContext;
    if (targetContext != null && targetContext.mounted) {
      _hasScrolledToToday = true;
      _isScrollPending = false;

      // 1. Initial jump to a position slightly above the target
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.3,
      );

      // 2. Short delay to let the jump settle
      await Future.delayed(const Duration(milliseconds: 100));

      // 3. Smooth scroll to the final position (alignment: 0.1)
      final currentContext = _todayKey.currentContext;
      if (currentContext != null && currentContext.mounted) {
        Scrollable.ensureVisible(
          currentContext,
          alignment: 0.1,
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeInOutCubic,
        );
      }
    } else {
      _isScrollPending = false;
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
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Full Schedule',
          style: theme.textTheme.titleLarge,
        ),
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

          return StreamBuilder<Map<String, int>>(
            stream: _progressStream,
            builder: (context, progressSnapshot) {
              final remoteProgress = progressSnapshot.data ?? {};

              // Clear optimistic overrides if they match remote data
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

              final now = DateTime.now();
              final todayDate = DateTime(now.year, now.month, now.day);

              final past = <GroupSchedule>[];
              final today = <GroupSchedule>[];
              final upcoming = <GroupSchedule>[];

              for (final s in fullSchedule) {
                final sDate = DateTime(s.date.year, s.date.month, s.date.day);
                if (sDate.isBefore(todayDate)) {
                  past.add(s);
                } else if (sDate.isAtSameMomentAs(todayDate)) {
                  today.add(s);
                } else {
                  upcoming.add(s);
                }
              }

              if (!_hasScrolledToToday &&
                  !_isScrollPending &&
                  (today.isNotEmpty || upcoming.isNotEmpty)) {
                _isScrollPending = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  unawaited(_scrollToToday());
                });
              }

              return ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  if (past.isNotEmpty) ...[
                    _buildSectionHeader(context, 'Past Readings'),
                    ...past.map((s) {
                      final dateId = _dateId(s.date);
                      final count = progress[dateId] ?? 0;
                      final isRead = s.chapters.isEmpty
                          ? count > 0
                          : count >= s.chapters.length;
                      return _buildScheduleItem(
                        context,
                        s,
                        isPast: true,
                        isRead: isRead,
                      );
                    }),
                    const SizedBox(height: 16),
                  ],
                  if (today.isNotEmpty) ...[
                    _buildSectionHeader(context, 'Today', isHighlight: true),
                    ...today.map((s) {
                      final dateId = _dateId(s.date);
                      final count = progress[dateId] ?? 0;
                      final isRead = s.chapters.isEmpty
                          ? count > 0
                          : count >= s.chapters.length;
                      return _buildTodayItem(
                        context,
                        s,
                        isRead: isRead,
                        key: _todayKey,
                      );
                    }),
                    const SizedBox(height: 16),
                  ],
                  if (upcoming.isNotEmpty) ...[
                    _buildSectionHeader(context, 'Upcoming'),
                    ...upcoming.map((s) {
                      final isFirstUpcoming = s == upcoming.first;
                      final dateId = _dateId(s.date);
                      final count = progress[dateId] ?? 0;
                      final isRead = s.chapters.isEmpty
                          ? count > 0
                          : count >= s.chapters.length;
                      return _buildScheduleItem(
                        context,
                        s,
                        isRead: isRead,
                        key: (today.isEmpty && isFirstUpcoming)
                            ? _todayKey
                            : null,
                      );
                    }),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title,
      {bool isHighlight = false}) {
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

  Widget _buildScheduleItem(BuildContext context, GroupSchedule schedule,
      {bool isPast = false, bool isRead = false, Key? key}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final opacity = isPast ? 0.7 : 1.0;

    return Opacity(
      key: key,
      opacity: opacity,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: widget.isMember ? () => _handleToggle(schedule, isRead) : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: isRead
                  ? Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.2),
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 56, // min-w-[3.5rem] -> 56px
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
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
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
                      color: colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                if (isRead)
                  Icon(
                    Icons.check,
                    color: colorScheme.primary.withValues(alpha: 0.5),
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTodayItem(BuildContext context, GroupSchedule schedule,
      {bool isRead = false, Key? key}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: widget.isMember ? () => _handleToggle(schedule, isRead) : null,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: isRead ? 0.8 : 0.5),
              width: isRead ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
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
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                      ),
                    ),
                    Text(
                      _formatDayOfWeek(schedule.date),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary.withValues(alpha: 0.8),
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
                      schedule.chapters.join(', '),
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              if (isRead)
                Icon(
                  Icons.check,
                  color: colorScheme.primary,
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
