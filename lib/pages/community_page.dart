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
import '../theme/app_theme.dart';
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
            decoration: const BoxDecoration(
              color: Colors.transparent,
            ),
            child: AnimatedBuilder(
              animation: _tabController,
              builder: (context, child) {
                return TabBar(
                  controller: _tabController,
                  labelColor: AppTheme.primary90,
                  unselectedLabelColor: AppTheme.neutral90,
                  indicator: const BoxDecoration(),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  tabs: [
                    _buildTab(0, Icons.groups_outlined, 'Groups'),
                    _buildTab(1, Icons.view_agenda_outlined, 'Feed'),
                    _buildTab(2, Icons.face_outlined, 'Friends'),
                  ],
                );
              },
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

  Widget _buildTab(int index, IconData icon, String label) {
    final isSelected = _tabController.index == index;
    return Tab(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary30 : AppTheme.neutral22,
          borderRadius: BorderRadius.circular(isSelected ? 99 : 16),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16), // Inner padding
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 4),
            Text(label, style: AppTextStyles.body.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 13,
            )),
          ],
        ),
      ),
    );
  }
}
