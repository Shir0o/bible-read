import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_member_progress.dart';
import '../models/group_schedule.dart';
import '../models/read_log.dart';
// Kept for compatibility if needed, though mostly replaced
import '../services/error_logger.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../services/reading_plan_service.dart';
import '../services/reading_status_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import 'full_schedule_page.dart';
import 'group_detail_page.dart';
import 'groups_page.dart';
import '../widgets/skeletons/friends_activity_skeleton.dart';
import '../widgets/skeletons/journey_progress_card_skeleton.dart';
import '../widgets/app_header.dart';
import '../widgets/skeleton_loader.dart';

class CommunityPage extends StatefulWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final GroupService groupService;
  final FriendService friendService;
  final ReadingPlanService readingPlanService;
  final ReadingStatusService readingStatusService;
  final VibrationService vibrationService;

  final Future<void> Function({
    required String ownerUid,
    required String likerName,
  }) onSendLikeNotification;
  final Future<void> Function({
    required String ownerUid,
    required String commenterName,
  }) onSendCommentNotification;
  final DateTime Function() dateProvider;

  // Optional builder kept for compatibility
  final Widget Function({
    Key? key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    required Future<void> Function(
            {required String ownerUid, required String likerName})
        onSendLikeNotification,
    required Future<void> Function(
            {required String ownerUid, required String commenterName})
        onSendCommentNotification,
  })? readLogBuilder;

  const CommunityPage({
    super.key,
    required this.auth,
    required this.firestore,
    required this.groupService,
    required this.friendService,
    required this.readingPlanService,
    required this.readingStatusService,
    required this.vibrationService,
    required this.onSendLikeNotification,
    required this.onSendCommentNotification,
    required this.dateProvider,
    this.readLogBuilder,
  });

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage>
    with AutomaticKeepAliveClientMixin {
  late Stream<List<Group>> _groupsStream;
  List<ReadLog> _friendLogs = [];
  List<GroupSchedule>? _initialGroupSchedule;
  List<GroupMemberProgressData>? _initialGroupProgress;
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _groupsStream = const Stream.empty();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = widget.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    if (!_isLoading) {
      setState(() => _isLoading = true);
    }

    _groupsStream = widget.groupService.groupsForUser(user.uid);

    try {
      final results = await Future.wait([
        _groupsStream.first
            .timeout(const Duration(seconds: 5), onTimeout: () => []),
        _getFriendsActivity(),
      ]);

      final groups = results[0] as List<Group>;
      final logs = results[1] as List<ReadLog>;

      // If we have groups, pre-fetch details for the first one to avoid flashing
      if (groups.isNotEmpty) {
        final firstGroup = groups.first;
        final details = await Future.wait([
          widget.groupService.schedule(firstGroup.id).first.timeout(
                const Duration(seconds: 2),
                onTimeout: () => [],
              ),
          widget.groupService
              .memberOverallCompletion(firstGroup.id, includeUid: user.uid)
              .first
              .timeout(
                const Duration(seconds: 2),
                onTimeout: () => [],
              ),
        ]);

        if (mounted) {
          setState(() {
            _initialGroupSchedule = details[0] as List<GroupSchedule>;
            _initialGroupProgress = details[1] as List<GroupMemberProgressData>;
          });
        }
      }

      if (mounted) {
        setState(() {
          _friendLogs = logs;
          _isLoading = false;
        });
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<List<ReadLog>> _getFriendsActivity() async {
    final user = widget.auth.currentUser;
    if (user == null) return [];

    try {
      // 1. Get friends
      final friendsSnap = await widget.friendService.friends(user.uid).first;
      final friendUids = friendsSnap.map((f) => f.uid).toSet();
      // Include current user
      friendUids.add(user.uid);

      // 2. Get today's logs
      final now = widget.dateProvider();
      final dateKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final entriesSnap = await widget.firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .get();

      final logs = await Future.wait(entriesSnap.docs.map((doc) {
        return ReadLog.fromFirestore(doc, currentUid: user.uid);
      }));

      // 3. Filter by friends + self
      final filtered =
          logs.where((log) => friendUids.contains(log.uid)).toList();

      // Sort by timestamp if available, else name
      filtered.sort((a, b) {
        if (a.timestamp != null && b.timestamp != null) {
          return b.timestamp!.compareTo(a.timestamp!);
        }
        return a.name.compareTo(b.name);
      });

      return filtered;
    } catch (e, st) {
      ErrorLogger.log(e, st);
      return [];
    }
  }

  Future<void> _toggleLike(String logUid) async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    final index = _friendLogs.indexWhere((log) => log.uid == logUid);
    if (index == -1) return;
    final original = _friendLogs[index];

    final likerName = (user.displayName ?? '').split(' ').first;
    final now = widget.dateProvider();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final likeRef = widget.firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc(logUid)
        .collection('likes')
        .doc(user.uid);

    // Optimistic update
    List<String> updatedNames = List.from(original.likeNames);
    bool newLikedState = !original.liked;

    if (original.liked) {
      updatedNames.remove(likerName);
    } else {
      updatedNames.add(likerName);
    }

    setState(() {
      _friendLogs[index] = original.copyWith(
        liked: newLikedState,
        likeNames: updatedNames,
      );
    });

    widget.vibrationService.lightImpact();

    try {
      if (original.liked) {
        await likeRef.delete();
      } else {
        await likeRef.set({'timestamp': Timestamp.now(), 'name': likerName});
        if (logUid != user.uid) {
          await widget.onSendLikeNotification(
              ownerUid: logUid, likerName: likerName);
        }
      }
    } catch (e) {
      // Revert
      if (mounted) {
        setState(() {
          _friendLogs[index] = original;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = widget.auth.currentUser;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: CustomScrollView(
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: AppHeader(
                  auth: widget.auth,
                  firestore: widget.firestore,
                  vibrationService: widget.vibrationService,
                  dateProvider: widget.dateProvider,
                ),
              ),

              // Group Progress
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Group Progress',
                              style: AppTextStyles.title(context).copyWith(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => GroupsPage(
                                      groupService: widget.groupService,
                                      auth: widget.auth,
                                      vibrationService: widget.vibrationService,
                                    ),
                                  ),
                                );
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: colorScheme.primary,
                                textStyle: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              child: const Text('View All'),
                            ),
                          ],
                        ),
                      ),
                      StreamBuilder<List<Group>>(
                        stream: _groupsStream,
                        builder: (context, snapshot) {
                          return SkeletonLoader(
                            loading: _isLoading,
                            minTime: const Duration(milliseconds: 1000),
                            skeleton: const JourneyProgressCardSkeleton(
                              padding: EdgeInsets.zero,
                            ),
                            child: (snapshot.hasData &&
                                    snapshot.data!.isNotEmpty)
                                ? _GroupProgressCard(
                                    group: snapshot.data!.first,
                                    groupService: widget.groupService,
                                    auth: widget.auth,
                                    user: user,
                                    vibrationService: widget.vibrationService,
                                    initialSchedule: _initialGroupSchedule,
                                    initialProgress: _initialGroupProgress,
                                  )
                                : _buildEmptyGroupState(context, colorScheme),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Friends Activity Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Text(
                    'Friends Activity',
                    style: AppTextStyles.title(context).copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // Friends Activity List
              SliverSkeletonLoader(
                loading: _isLoading,
                minTime: const Duration(milliseconds: 1000),
                skeleton: const FriendsActivitySkeleton(),
                child: _friendLogs.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              'No recent activity.',
                              style: AppTextStyles.body(context).copyWith(
                                  color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final log = _friendLogs[index];
                              return _ActivityItem(
                                log: log,
                                onLike: () => _toggleLike(log.uid),
                              );
                            },
                            childCount: _friendLogs.length,
                          ),
                        ),
                      ),
              ),

              const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyGroupState(BuildContext context, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.1)),
      ),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.group_outlined,
              size: 48, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'No active groups',
            style: AppTextStyles.title(context)
                .copyWith(fontSize: 16, color: colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            'Join a group to see progress here.',
            style: AppTextStyles.body(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _GroupProgressCard extends StatelessWidget {
  final Group group;
  final GroupService groupService;
  final FirebaseAuth auth;
  final User user;
  final VibrationService vibrationService;
  final List<GroupSchedule>? initialSchedule;
  final List<GroupMemberProgressData>? initialProgress;

  const _GroupProgressCard({
    required this.group,
    required this.groupService,
    required this.auth,
    required this.user,
    required this.vibrationService,
    this.initialSchedule,
    this.initialProgress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            vibrationService.lightImpact();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroupDetailPage(
                  group: group,
                  groupService: groupService,
                  auth: auth,
                  vibrationService: vibrationService,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Group Icon
                    Container(
                      width: 80,
                      height: 100,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              colorScheme.outlineVariant.withValues(alpha: 0.2),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          Icons.groups,
                          size: 36,
                          color: colorScheme.primary.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: StreamBuilder<List<GroupSchedule>>(
                        stream: groupService.schedule(group.id),
                        initialData: initialSchedule,
                        builder: (context, scheduleSnap) {
                          final schedule = scheduleSnap.data ?? [];
                          // Calculate days
                          final now = DateTime.now();
                          final today = DateTime(now.year, now.month, now.day);

                          int currentDay = 0;
                          final totalDays = schedule.length;

                          if (schedule.isNotEmpty) {
                            // Find index of today or next upcoming
                            final index = schedule
                                .indexWhere((s) => !s.date.isBefore(today));
                            if (index != -1) {
                              if (schedule[index]
                                  .date
                                  .isAtSameMomentAs(today)) {
                                currentDay = index + 1;
                              } else {
                                currentDay = index + 1; // Upcoming
                              }
                            } else {
                              // All in past
                              currentDay = totalDays;
                            }
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.name,
                                style: AppTextStyles.title(context)
                                    .copyWith(fontSize: 18),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Day $currentDay',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'of $totalDays • Collective Plan',
                                    style: AppTextStyles.body(context).copyWith(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              StreamBuilder<List<GroupMemberProgressData>>(
                                stream: groupService.memberOverallCompletion(
                                    group.id,
                                    includeUid: user.uid),
                                initialData: initialProgress,
                                builder: (context, progressSnap) {
                                  final members = progressSnap.data ?? [];
                                  final myProgress = members.firstWhere(
                                    (m) => m.uid == user.uid,
                                    orElse: () => GroupMemberProgressData(
                                        uid: '', name: '', completion: 0.0),
                                  );
                                  final percent = myProgress.completion;

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '${(percent * 100).toInt()}% of Schedule',
                                            style: AppTextStyles.body(context)
                                                .copyWith(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: LinearProgressIndicator(
                                          value: percent,
                                          minHeight: 8,
                                          backgroundColor: colorScheme
                                              .surfaceContainerHighest,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  colorScheme.primary),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.tonal(
                    onPressed: () {
                      vibrationService.lightImpact();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FullSchedulePage(
                            group: group,
                            groupService: groupService,
                            auth: auth,
                            vibrationService: vibrationService,
                            initialSchedule: initialSchedule,
                            isMember: false,
                          ),
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.secondaryContainer,
                      foregroundColor: colorScheme.onSecondaryContainer,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'View Schedule',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
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

class _ActivityItem extends StatelessWidget {
  final ReadLog log;
  final VoidCallback onLike;

  const _ActivityItem({
    required this.log,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Fallback time if timestamp is missing
    final timeString =
        log.timestamp != null ? _timeAgo(log.timestamp!) : 'today';

    final bool isComment = log.comments.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar with badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.surfaceContainerHighest,
                ),
                alignment: Alignment.center,
                child: Text(
                  log.name.isNotEmpty ? log.name[0].toUpperCase() : '?',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant),
                ),
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color:
                        isComment ? colorScheme.tertiary : colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: colorScheme.surfaceContainer, width: 2),
                  ),
                  child: Icon(
                    isComment ? Icons.chat_bubble : Icons.check,
                    size: 10,
                    color: isComment
                        ? colorScheme.onTertiary
                        : colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: AppTextStyles.body(context)
                        .copyWith(color: colorScheme.onSurface),
                    children: [
                      TextSpan(
                          text: log.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (isComment) ...[
                        const TextSpan(text: ' commented on '),
                        TextSpan(
                            text:
                                'daily reading', // Placeholder since we don't have book ref
                            style: TextStyle(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600)),
                      ] else ...[
                        const TextSpan(text: ' completed '),
                        TextSpan(
                            text: 'daily reading',
                            style: TextStyle(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                ),
                if (isComment)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: colorScheme.outlineVariant
                              .withValues(alpha: 0.1)),
                    ),
                    child: Text(
                      '"${log.comments.last.message}"',
                      style: AppTextStyles.body(context).copyWith(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  timeString,
                  style: AppTextStyles.body(context).copyWith(
                      fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              log.liked ? Icons.favorite : Icons.favorite_border,
              color: log.liked ? Colors.red : colorScheme.onSurfaceVariant,
              size: 20,
            ),
            onPressed: onLike,
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}
