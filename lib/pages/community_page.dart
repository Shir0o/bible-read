import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

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
import 'groups_page.dart';
import '../widgets/skeletons/friends_activity_skeleton.dart';
import '../widgets/skeletons/journey_progress_card_skeleton.dart';
import '../widgets/app_header.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/community/community_group_progress_card.dart';
import '../widgets/community/community_activity_item.dart';
import '../widgets/community/empty_group_state.dart';

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
    required Future<void> Function({
      required String ownerUid,
      required String likerName,
    }) onSendLikeNotification,
    required Future<void> Function({
      required String ownerUid,
      required String commenterName,
    }) onSendCommentNotification,
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
  late Stream<List<ReadLog>> _friendsActivityStream;
  List<ReadLog> _friendLogs = [];
  final Map<String, ReadLog> _optimisticLogs = {};
  List<GroupSchedule>? _initialGroupSchedule;
  List<GroupMemberProgressData>? _initialGroupProgress;
  bool _isLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _groupsStream = const Stream.empty();
    _friendsActivityStream = const Stream.empty();
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
    _friendsActivityStream = _getFriendsActivityStream();

    try {
      final results = await Future.wait([
        _groupsStream.first.timeout(
          const Duration(seconds: 5),
          onTimeout: () => [],
        ),
        _friendsActivityStream.first.timeout(
          const Duration(seconds: 5),
          onTimeout: () => [],
        ),
      ]);

      final groups = results[0] as List<Group>;
      final logs = results[1] as List<ReadLog>;

      // If we have groups, pre-fetch details for the first one to avoid flashing
      if (groups.isNotEmpty) {
        final firstGroup = groups.first;
        final details = await Future.wait([
          widget.groupService
              .schedule(firstGroup.id)
              .first
              .timeout(const Duration(seconds: 2), onTimeout: () => []),
          widget.groupService
              .memberOverallCompletion(firstGroup.id, includeUid: user.uid)
              .first
              .timeout(const Duration(seconds: 2), onTimeout: () => []),
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

  Stream<List<ReadLog>> _getFriendsActivityStream() {
    final user = widget.auth.currentUser;
    if (user == null) return Stream.value([]);

    // 1. Get friends stream
    return widget.friendService.friends(user.uid).switchMap((friendsSnap) {
      final friendUids = friendsSnap.map((f) => f.uid).toSet();
      // Include current user
      friendUids.add(user.uid);

      // 2. Get today's logs stream
      final now = widget.dateProvider();
      final dateKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      return widget.firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .snapshots()
          .asyncMap((entriesSnap) async {
        final logs = await Future.wait(
          entriesSnap.docs.map((doc) {
            return ReadLog.fromFirestore(doc, currentUid: user.uid);
          }),
        );

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
      });
    });
  }

  Future<void> _toggleLike(String logUid) async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    final baseLogs = _friendLogs; // Use last known logs as fallback
    final index = baseLogs.indexWhere((log) => log.uid == logUid);
    if (index == -1) return;
    final original = baseLogs[index];

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

    final updatedLog = original.copyWith(
      liked: newLikedState,
      likeNames: updatedNames,
    );

    setState(() {
      _optimisticLogs[logUid] = updatedLog;
    });

    widget.vibrationService.lightImpact();

    try {
      if (original.liked) {
        await likeRef.delete();
      } else {
        await likeRef.set({'timestamp': Timestamp.now(), 'name': likerName});
        if (logUid != user.uid) {
          await widget.onSendLikeNotification(
            ownerUid: logUid,
            likerName: likerName,
          );
        }
      }
      // After success, we can eventually clear from optimisticLogs when stream catches up,
      // but for simplicity we can just leave it until next build or clear it here.
      // Wait, if we clear it here, the stream snapshot might still be the old one.
      // Better to clear it when the stream emits a matching state.
    } catch (e) {
      // Revert
      if (mounted) {
        setState(() {
          _optimisticLogs.remove(logUid);
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
                          horizontal: 4,
                          vertical: 8,
                        ),
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
                                  fontWeight: FontWeight.bold,
                                ),
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
                                ? CommunityGroupProgressCard(
                                    group: snapshot.data!.first,
                                    groupService: widget.groupService,
                                    auth: widget.auth,
                                    user: user,
                                    vibrationService: widget.vibrationService,
                                    initialSchedule: _initialGroupSchedule,
                                    initialProgress: _initialGroupProgress,
                                  )
                                : const EmptyGroupState(),
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
                  padding: const EdgeInsets.fromLTRB(20, 24, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Friends Activity',
                        style: AppTextStyles.title(
                          context,
                        ).copyWith(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),

              // Friends Activity List
              StreamBuilder<List<ReadLog>>(
                stream: _friendsActivityStream,
                builder: (context, snapshot) {
                  // Capture current logs for fallback
                  if (snapshot.hasData) {
                    _friendLogs = snapshot.data!;
                  }

                  final baseLogs = snapshot.data ?? _friendLogs;
                  // Apply optimistic overrides
                  final logs = baseLogs.map((log) {
                    final override = _optimisticLogs[log.uid];
                    if (override != null) {
                      // If the stream data matches the override, we can clear it
                      if (override.liked == log.liked) {
                        _optimisticLogs.remove(log.uid);
                        return log;
                      }
                      return override;
                    }
                    return log;
                  }).toList();

                  return SliverSkeletonLoader(
                    loading: _isLoading,
                    minTime: const Duration(milliseconds: 1000),
                    skeleton: const FriendsActivitySkeleton(),
                    child: logs.isEmpty
                        ? SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Center(
                                child: Text(
                                  'No recent activity.',
                                  style: AppTextStyles.body(context).copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final log = logs[index];
                                return CommunityActivityItem(
                                  log: log,
                                  onLike: () => _toggleLike(log.uid),
                                );
                              }, childCount: logs.length),
                            ),
                          ),
                  );
                },
              ),

              const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
            ],
          ),
        ),
      ),
    );
  }
}
