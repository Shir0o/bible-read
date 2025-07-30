import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/achievement_service.dart';
import '../models/achievement_definition.dart';
import '../widgets/common_styles.dart';
import '../widgets/badge_icon.dart';

class AchievementsPage extends StatelessWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  AchievementsPage(
      {super.key, FirebaseFirestore? firestore, FirebaseAuth? auth})
      : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    return Scaffold(
      appBar: CommonStyles.buildAppBar('Achievements'),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: user == null
            ? const Center(
                child: Text('Please sign in to view your achievements.'),
              )
            : StreamBuilder<Set<String>>(
                stream: AchievementService(firestore: firestore)
                    .unlockedAchievementIds(user.uid),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                        child: Text('Failed to load achievements'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final unlocked = snapshot.data!;
                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.9,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                    ),
                    itemCount: allAchievements.length,
                    itemBuilder: (context, index) {
                      final def = allAchievements[index];
                      final isUnlocked = unlocked.contains(def.id);
                      return Column(
                        children: [
                          BadgeIcon(
                            assetPath: def.assetPath,
                            locked: !isUnlocked,
                            size: 64,
                          ),
                          const SizedBox(height: 8),
                          Text(def.title, textAlign: TextAlign.center),
                        ],
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}
