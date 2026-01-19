import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/friend_service.dart';
import '../services/vibration_service.dart';
import '../services/exercise_tracker_service.dart';
import '../widgets/common_styles.dart';
import '../services/achievement_service.dart';
import '../services/seasonal_challenge_service.dart';

// These imports assume we will refactor or use existing pages
import 'achievements_page.dart';
import 'leaderboard_page.dart' as lb;
import 'seasonal_challenges_page.dart';
import 'exercise_challenges_page.dart';

class ChallengesPage extends StatefulWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FriendService friendService;
  final VibrationService vibrationService;
  final ExerciseTrackerService exerciseTrackerService;

  const ChallengesPage({
    super.key,
    required this.auth,
    required this.firestore,
    required this.friendService,
    required this.vibrationService,
    required this.exerciseTrackerService,
  });

  @override
  State<ChallengesPage> createState() => _ChallengesPageState();
}

class _ChallengesPageState extends State<ChallengesPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
        title: const Text('Challenges'),
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        titleTextStyle: AppTextStyles.title.copyWith(fontSize: 22),
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          indicatorColor: colorScheme.primary,
          dividerColor: Colors.transparent,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Seasonal'),
            Tab(text: 'Leaderboard'),
            Tab(text: 'Achievements'),
            Tab(text: 'Exercise'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SeasonalChallengesView(
            auth: widget.auth,
            // Assuming we need to instantiate the service here or pass it. 
            // SeasonalChallengesPage wrapper instantiated it?
            // Let's check constructor of SeasonalChallengesPage/View.
            // View takes service.
            service: SeasonalChallengeService(firestore: widget.firestore),
          ),
          lb.LeaderboardView(
            firestore: widget.firestore,
            auth: widget.auth,
            friendService: widget.friendService,
          ),
          AchievementsView(
             auth: widget.auth,
             achievementService: AchievementService(firestore: widget.firestore),
          ),
          ExerciseChallengesView(
             service: widget.exerciseTrackerService,
          ),
        ],
      ),
    );
  }
}
