import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/achievement_service.dart';
import '../models/achievement_definition.dart';
import '../widgets/common_styles.dart';
import '../widgets/achievement_list_item.dart';

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
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: allAchievements.length,
                    separatorBuilder: (_, __) => const Divider(height: 0),
                    itemBuilder: (context, index) {
                      final def = allAchievements[index];
                      final isUnlocked = unlocked.contains(def.id);
                      return AchievementListItem(
                        definition: def,
                        unlocked: isUnlocked,
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}
