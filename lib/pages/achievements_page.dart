import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/achievement.dart';
import '../services/achievement_service.dart';
// import '../services/error_logger.dart'; // Add if needed for error handling
import '../widgets/common_styles.dart';

class AchievementsView extends StatelessWidget {
  final FirebaseAuth auth;
  final AchievementService achievementService;

  const AchievementsView({
    super.key,
    required this.auth,
    required this.achievementService,
  });

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) return const Center(child: Text('Please sign in'));

    return StreamBuilder<List<Achievement>>(
      stream: achievementService.achievements(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Error loading achievements'));
        }

        final achievements = snapshot.data ?? [];
        if (achievements.isEmpty) {
          return const Center(
              child: Text('No achievements yet. Keep reading!'));
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.8,
          ),
          itemCount: achievements.length,
          itemBuilder: (context, index) {
            return _AchievementCard(achievement: achievements[index]);
          },
        );
      },
    );
  }
}

class _AchievementCard extends StatelessWidget {
  final Achievement achievement;

  const _AchievementCard({required this.achievement});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: Colors.amber.withValues(alpha: 0.2),
          child: const Icon(Icons.emoji_events, color: Colors.amber, size: 30),
        ),
        const SizedBox(height: 8),
        Text(
          achievement.title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        Text(
          _formatDate(achievement.dateUnlocked),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 10, color: Theme.of(context).colorScheme.secondary),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

// Wrapper for backward compatibility
class AchievementsPage extends StatelessWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final AchievementService achievementService;

  AchievementsPage({
    super.key,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    AchievementService? achievementService,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        achievementService = achievementService ??
            AchievementService(
                firestore: firestore ?? FirebaseFirestore.instance);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar(context, 'Achievements'),
      body: AchievementsView(
        auth: auth,
        achievementService: achievementService,
      ),
    );
  }
}
