import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_schedule.dart';
import '../services/error_logger.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../services/reading_plan_service.dart';
import '../services/reading_status_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import 'groups_page.dart';
import 'group_detail_page.dart';
import 'full_schedule_page.dart';
import '../widgets/skeletons/journey_progress_card_skeleton.dart';
import '../widgets/app_header.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/group_card.dart';
import '../widgets/community/community_reading_hero.dart';
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
  List<GroupSchedule>? _initialGroupSchedule;
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
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (!_isLoading) {
      setState(() => _isLoading = true);
    }

    _groupsStream = widget.groupService.groupsForUser(user.uid);

    try {
      final groups = await _groupsStream.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => [],
      );

      // Pre-fetch the first group's schedule so the hero doesn't flash.
      if (groups.isNotEmpty) {
        final schedule = await widget.groupService
            .schedule(groups.first.id)
            .first
            .timeout(const Duration(seconds: 2), onTimeout: () => []);
        if (mounted) {
          setState(() => _initialGroupSchedule = schedule);
        }
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openGroupsPage() {
    widget.vibrationService.lightImpact();
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
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = widget.auth.currentUser;
    final colorScheme = Theme.of(context).colorScheme;

    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: AppHeader(
                  auth: widget.auth,
                  firestore: widget.firestore,
                  vibrationService: widget.vibrationService,
                  dateProvider: widget.dateProvider,
                  eyebrow: 'Together',
                  title: 'Community',
                ),
              ),
              SliverToBoxAdapter(
                child: StreamBuilder<List<Group>>(
                  stream: _groupsStream,
                  builder: (context, snapshot) {
                    final groups = snapshot.data ?? const <Group>[];
                    return SkeletonLoader(
                      loading: _isLoading,
                      minTime: const Duration(milliseconds: 800),
                      skeleton: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: JourneyProgressCardSkeleton(
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      child: groups.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Column(
                                children: [
                                  const EmptyGroupState(),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 52,
                                    child: FilledButton.icon(
                                      onPressed: _openGroupsPage,
                                      icon: const Icon(
                                        Icons.group_add_outlined,
                                        size: 19,
                                      ),
                                      label: const Text(
                                        'Find or create a group',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : _buildGroupsContent(context, user, groups),
                    );
                  },
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupsContent(
    BuildContext context,
    User user,
    List<Group> groups,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = groups.first;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The shared daily reading — the centrepiece of the tab.
          CommunityReadingHero(
            group: primary,
            groupService: widget.groupService,
            user: user,
            vibrationService: widget.vibrationService,
            dateProvider: widget.dateProvider,
            initialSchedule: _initialGroupSchedule,
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Your reading groups',
                  style: AppTextStyles.title(context).copyWith(fontSize: 19),
                ),
                TextButton(
                  onPressed: _openGroupsPage,
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.primary,
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  child: const Text('Manage'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          for (final group in groups)
            GroupCard(
              group: group,
              groupService: widget.groupService,
              onTap: () {
                widget.vibrationService.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupDetailPage(
                      group: group,
                      groupService: widget.groupService,
                      auth: widget.auth,
                      vibrationService: widget.vibrationService,
                    ),
                  ),
                );
              },
              onViewSchedule: () {
                widget.vibrationService.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FullSchedulePage(
                      group: group,
                      groupService: widget.groupService,
                      auth: widget.auth,
                      vibrationService: widget.vibrationService,
                      initialSchedule:
                          group.id == primary.id ? _initialGroupSchedule : null,
                      isMember: true,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
