import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/read_log.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';
import '../services/error_logger.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../services/notification_service.dart';
import '../services/reading_plan_service.dart';
import '../services/reading_status_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';

// Needed import for NotificationCenterPage in navigation
import 'notification_center_page.dart';

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

  // Optional builder kept for compatibility if passed, but we are rewriting the UI
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

class _CommunityPageState extends State<CommunityPage> {
  late Stream<List<UserPlanProgress>> _plansStream;
  List<ReadLog> _friendLogs = [];
  bool _loadingLogs = true;

  @override
  void initState() {
    super.initState();
    final user = widget.auth.currentUser;
    if (user != null) {
      _plansStream = widget.readingPlanService.getActivePlans(user.uid);
      _fetchFriendsActivity();
    } else {
      _plansStream = Stream.value([]);
      _loadingLogs = false;
    }
  }

  Future<void> _fetchFriendsActivity() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    setState(() => _loadingLogs = true);

    try {
      // 1. Get friends
      final friendsSnap = await widget.friendService.friends(user.uid).first;
      final friendUids = friendsSnap.map((f) => f.uid).toSet();

      // 2. Get today's logs
      final now = widget.dateProvider();
      final dateKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // We fetch all entries for today because we can't filter by UID list efficiently if large,
      // but assuming reasonable daily users.
      // Optimization: If friends list is small (<10), we could get individual docs.
      // But ReadLogView fetches all, so we'll stick to that for consistency/cache.
      final entriesSnap = await widget.firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .get();

      final logs = await Future.wait(entriesSnap.docs.map((doc) {
        return ReadLog.fromFirestore(doc, currentUid: user.uid);
      }));

      // 3. Filter by friends
      final filtered = logs.where((log) => friendUids.contains(log.uid)).toList();

      // Sort by timestamp if available, else name
      filtered.sort((a, b) {
        if (a.timestamp != null && b.timestamp != null) {
          return b.timestamp!.compareTo(a.timestamp!);
        }
        return a.name.compareTo(b.name);
      });

      if (mounted) {
        setState(() {
          _friendLogs = filtered;
          _loadingLogs = false;
        });
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        setState(() => _loadingLogs = false);
      }
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
          await widget.onSendLikeNotification(ownerUid: logUid, likerName: likerName);
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
    final user = widget.auth.currentUser;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (user == null) return const SizedBox.shrink();

    final firstName = (user.displayName ?? 'Friend').split(' ').first;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _fetchFriendsActivity();
            setState(() {}); // Trigger rebuilds for streams
          },
          child: CustomScrollView(
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  child: Row(
                    children: [
                      // Avatar
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.surfaceContainerHighest,
                          image: user.photoURL != null
                              ? DecorationImage(
                                  image: CachedNetworkImageProvider(user.photoURL!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: user.photoURL == null
                            ? Icon(Icons.person, color: colorScheme.onSurfaceVariant)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Good Morning,',
                              style: AppTextStyles.body.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              firstName,
                              style: AppTextStyles.title.copyWith(
                                color: colorScheme.primary,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Notification Button
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.surfaceContainer,
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.1)),
                        ),
                        child: IconButton(
                          icon: Icon(Icons.notifications_outlined, 
                            color: colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                          onPressed: () {
                             // Assuming standard nav to notifications
                             Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NotificationCenterPage(
                                  service: NotificationService(firestore: widget.firestore),
                                  auth: widget.auth,
                                  vibrationService: widget.vibrationService,
                                ),
                              ),
                            );
                          },
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Current Progress
              SliverToBoxAdapter(
                child: StreamBuilder<List<UserPlanProgress>>(
                  stream: _plansStream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const SizedBox.shrink(); // Hide if no plan
                    }
                    final progress = snapshot.data!.first;

                    return FutureBuilder<ReadingPlan?>(
                      future: widget.readingPlanService.getPlanById(progress.planId),
                      builder: (context, planSnap) {
                        if (!planSnap.hasData) return const SizedBox.shrink();
                        final plan = planSnap.data!;
                        final completedCount = progress.completedDays.length;
                        final totalDays = plan.durationDays;
                        final percent = totalDays > 0 ? completedCount / totalDays : 0.0;
                        final currentDay = completedCount + 1; // Assuming linear

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Current Progress',
                                      style: AppTextStyles.title.copyWith(fontSize: 18),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        // View All
                                      },
                                      child: const Text('View All'),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.1)),
                                ),
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Book Cover Placeholder
                                        Container(
                                          width: 80,
                                          height: 110,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(12),
                                            color: colorScheme.surfaceContainerHighest,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.1),
                                                blurRadius: 8,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          alignment: Alignment.center,
                                          child: Icon(Icons.book, size: 32, color: colorScheme.onSurfaceVariant),
                                        ),
                                        const SizedBox(width: 20),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                plan.title,
                                                style: AppTextStyles.title.copyWith(fontSize: 18),
                                              ),
                                              const SizedBox(height: 6),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: colorScheme.secondaryContainer,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      'Day $currentDay',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: colorScheme.onSecondaryContainer,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'of $totalDays',
                                                    style: AppTextStyles.body.copyWith(
                                                      fontSize: 12,
                                                      color: colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 16),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    '${(percent * 100).toInt()}% Complete',
                                                    style: AppTextStyles.body.copyWith(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: colorScheme.onSurfaceVariant,
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
                                                  backgroundColor: colorScheme.surfaceContainerHighest,
                                                  valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: () {
                                          // Resume Reading - For now just a feedback
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Resuming plan...')),
                                          );
                                        },
                                        icon: const Icon(Icons.play_arrow_rounded),
                                        label: const Text('Resume Reading'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: colorScheme.secondaryContainer,
                                          foregroundColor: colorScheme.onSecondaryContainer,
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          textStyle: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // Friends Activity Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    'Friends Activity',
                    style: AppTextStyles.title.copyWith(fontSize: 18),
                  ),
                ),
              ),

              // Friends Activity List
              if (_loadingLogs)
                const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())))
              else if (_friendLogs.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No recent activity from friends.',
                        style: AppTextStyles.body.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
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
              
              const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
            ],
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
    final timeString = log.timestamp != null 
        ? _timeAgo(log.timestamp!) 
        : 'today';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           // Avatar
           Container(
             width: 40,
             height: 40,
             decoration: BoxDecoration(
               shape: BoxShape.circle,
               color: colorScheme.surfaceContainerHighest,
             ),
             // We don't have friend photo URL in ReadLog easily unless we fetch it. 
             // ReadLog only has 'name'. 
             // We'll use a generic icon or initials.
             alignment: Alignment.center,
             child: Text(
               log.name.isNotEmpty ? log.name[0].toUpperCase() : '?',
               style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
             ),
           ),
           const SizedBox(width: 16),
           Expanded(
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 RichText(
                   text: TextSpan(
                     style: AppTextStyles.body.copyWith(color: colorScheme.onSurface),
                     children: [
                       TextSpan(text: log.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                       const TextSpan(text: ' read today'), // Generic action since we don't have ref
                       if (log.comments.isNotEmpty)
                          const TextSpan(text: ' and commented'),
                     ],
                   ),
                 ),
                 const SizedBox(height: 4),
                 Text(
                   timeString,
                   style: AppTextStyles.body.copyWith(fontSize: 12, color: colorScheme.onSurfaceVariant),
                 ),
                 if (log.comments.isNotEmpty)
                   Container(
                     margin: const EdgeInsets.only(top: 8),
                     padding: const EdgeInsets.all(12),
                     decoration: BoxDecoration(
                       color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                       borderRadius: BorderRadius.circular(12),
                       border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.1)),
                     ),
                     child: Text(
                       '"${log.comments.last.message}"',
                       style: AppTextStyles.body.copyWith(
                         fontSize: 12, 
                         fontStyle: FontStyle.italic,
                         color: colorScheme.onSurfaceVariant,
                       ),
                     ),
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

