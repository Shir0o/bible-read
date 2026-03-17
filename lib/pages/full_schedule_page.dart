import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/group.dart';
import '../models/group_schedule.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';

class FullSchedulePage extends StatefulWidget {
  final Group group;
  final GroupService groupService;
  final FirebaseAuth auth;
  final VibrationService vibrationService;

  const FullSchedulePage({
    super.key,
    required this.group,
    required this.groupService,
    required this.auth,
    required this.vibrationService,
  });

  @override
  State<FullSchedulePage> createState() => _FullSchedulePageState();
}

class _FullSchedulePageState extends State<FullSchedulePage> {
  late Stream<List<GroupSchedule>> _scheduleStream;
  final ScrollController _scrollController = ScrollController();

  // Cache for read status to avoid refetching too often if we add that feature
  // For now, we mainly display the schedule.

  @override
  void initState() {
    super.initState();
    _scheduleStream = widget.groupService.schedule(widget.group.id);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final fullSchedule = snapshot.data!;
          if (fullSchedule.isEmpty) {
            return const Center(child: Text('No schedule available'));
          }

          // Sort schedule just in case
          fullSchedule.sort((a, b) => a.date.compareTo(b.date));

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

          return ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              if (past.isNotEmpty) ...[
                _buildSectionHeader(context, 'Past Readings'),
                ...past
                    .map((s) => _buildScheduleItem(context, s, isPast: true)),
                const SizedBox(height: 16),
              ],
              if (today.isNotEmpty) ...[
                _buildSectionHeader(context, 'Today', isHighlight: true),
                ...today.map((s) => _buildTodayItem(context, s)),
                const SizedBox(height: 16),
              ],
              if (upcoming.isNotEmpty) ...[
                _buildSectionHeader(context, 'Upcoming'),
                ...upcoming.map((s) => _buildScheduleItem(context, s)),
              ],
            ],
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
      {bool isPast = false}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final opacity = isPast ? 0.7 : 1.0;

    return Opacity(
      opacity: opacity,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
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
                  color: colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
            if (isPast)
              Icon(
                Icons.check_circle,
                color: colorScheme.primary,
                size: 24,
              )
            else
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.4),
                      width: 1,
                    )),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildTodayItem(BuildContext context, GroupSchedule schedule) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.5),
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
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.primary,
                  width: 2,
                )),
          )
        ],
      ),
    );
  }
}
