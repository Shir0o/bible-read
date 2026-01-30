import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/friendly_streak_service.dart';
import '../services/notification_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import 'friendly_streak_page.dart';
import 'notification_center_page.dart';

class InboxPage extends StatefulWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final VibrationService vibrationService;

  const InboxPage({
    super.key,
    required this.auth,
    required this.firestore,
    required this.vibrationService,
  });

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        titleTextStyle: AppTextStyles.title.copyWith(fontSize: 22),
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          indicatorColor: colorScheme.primary,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(
                icon: Icon(Icons.notifications_outlined),
                text: 'Notifications'),
            Tab(
                icon: Icon(Icons.local_fire_department_outlined),
                text: 'Streaks'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          NotificationCenterPage(
            service: NotificationService(firestore: widget.firestore),
            auth: widget.auth,
            vibrationService: widget.vibrationService,
          ),
          FriendlyStreakView(
            firestore: widget.firestore,
            auth: widget.auth,
            friendlyStreakService:
                FriendlyStreakService(firestore: widget.firestore),
          ),
        ],
      ),
    );
  }
}
