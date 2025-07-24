import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/achievement_service.dart';
import '../models/achievement.dart';
import '../widgets/common_styles.dart';

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
            : StreamBuilder<List<Achievement>>(
                stream: AchievementService(firestore: firestore)
                    .achievements(user.uid),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final data = snapshot.data ?? [];
                  if (data.isEmpty) {
                    return const Center(child: Text('No achievements yet.'));
                  }
                  return ListView.builder(
                    itemCount: data.length,
                    itemBuilder: (context, index) {
                      final a = data[index];
                      return ListTile(
                        leading: const Icon(Icons.star, color: Colors.amber),
                        title: Text(a.title),
                        subtitle: Text(
                          '${a.dateUnlocked.year}-${a.dateUnlocked.month}-${a.dateUnlocked.day}',
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}
