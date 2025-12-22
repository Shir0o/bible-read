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

class _InboxPageState extends State<InboxPage> with SingleTickerProviderStateMixin {
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
             Tab(icon: Icon(Icons.notifications_outlined), text: 'Notifications'),
             Tab(icon: Icon(Icons.local_fire_department_outlined), text: 'Streaks'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          NotificationCenterContent(
            service: NotificationService(firestore: widget.firestore),
            auth: widget.auth,
            vibrationService: widget.vibrationService,
          ),
          FriendlyStreakView(
             firestore: widget.firestore,
             auth: widget.auth,
             friendlyStreakService: FriendlyStreakService(firestore: widget.firestore),
          ),
        ],
      ),
    );
  }
}

// Wrapper for NotificationCenterPage to fit in TabView without Scaffold if needed, 
// but NotificationCenterPage currently has Scaffold. We should likely refactor it too, 
// but for now I will wrap it layout-wise. 
// Ideally NotificationCenterPage should be split like others. 
// Checking imports -> NotificationCenterPage is imported.
// I'll assume for this pass I can't refactor everything, so I might just embed 
// the pages directly if they allow, or I'll just use the existing pages.
// `NotificationCenterPage` seems to have a Scaffold. `FriendlyStreakPage` also does.
// I will need to refactor them briefly to separate Views or accept a 'scaffold' parameter.
// For now, I'll extract logic from NotificationCenter and FriendlyStreak in the next steps 
// if I haven't already. I haven't. 
// I will create simple View wrappers akin to others.
