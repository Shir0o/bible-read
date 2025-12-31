import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../services/reading_status_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/profile_button.dart';
import '../widgets/views/friends_view.dart';
import '../widgets/views/groups_view.dart';
import '../widgets/views/read_log_view.dart';

class CommunityPage extends StatefulWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final GroupService groupService;
  final FriendService friendService;
  final ReadingStatusService readingStatusService;
  final VibrationService vibrationService;
  
  // Dependencies for ReadLogView
  final Future<void> Function({
    required String ownerUid,
    required String likerName,
  }) onSendLikeNotification;
  final Future<void> Function({
    required String ownerUid,
    required String commenterName,
  }) onSendCommentNotification;
  final DateTime Function() dateProvider;

  const CommunityPage({
    super.key,
    required this.auth,
    required this.firestore,
    required this.groupService,
    required this.friendService,
    required this.readingStatusService,
    required this.vibrationService,
    required this.onSendLikeNotification,
    required this.onSendCommentNotification,
    required this.dateProvider,
  });

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tabController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      animationDuration: const Duration(milliseconds: 350),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community'),
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        titleTextStyle: AppTextStyles.title.copyWith(fontSize: 22),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Reduced horizontal margin
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(32),
            ),
            padding: const EdgeInsets.all(3), // Reduced padding
            child: TabBar(
              controller: _tabController,
              labelColor: colorScheme.onSurface,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              dividerColor: Colors.transparent,
              overlayColor: MaterialStateProperty.all(Colors.transparent),
              splashBorderRadius: BorderRadius.circular(28),
              labelStyle: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 13, // Slightly smaller font
              ),
              unselectedLabelStyle: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.groups_outlined, size: 16), // Smaller icon
                      SizedBox(width: 4), // Reduced gap
                      Text('Groups'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.view_agenda_outlined, size: 16),
                      SizedBox(width: 4),
                      Text('Feed'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.face_outlined, size: 16),
                      SizedBox(width: 4),
                      Text('Friends'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          GroupsView(
            groupService: widget.groupService,
            auth: widget.auth,
            vibrationService: widget.vibrationService,
          ),
          ReadLogView(
            firestore: widget.firestore,
            auth: widget.auth,
            readingStatusService: widget.readingStatusService,
            onSendLikeNotification: widget.onSendLikeNotification,
            onSendCommentNotification: widget.onSendCommentNotification,
            dateProvider: widget.dateProvider,
            tabController: _tabController,
          ),
          FriendsView(
            friendService: widget.friendService,
            auth: widget.auth,
            vibrationService: widget.vibrationService,
          ),
        ],
      ),
    );
  }
}
