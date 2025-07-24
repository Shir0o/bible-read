import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/achievement.dart';
import '../services/achievement_service.dart';

/// Displays a count of unlocked achievements for the current user.
class AchievementSummary extends StatelessWidget {
  /// Firestore instance for reading achievements.
  final FirebaseFirestore firestore;

  /// Firebase authentication instance to read the current user.
  final FirebaseAuth auth;

  /// Creates an [AchievementSummary].
  AchievementSummary({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<List<Achievement>>(
      stream: AchievementService(firestore: firestore).achievements(user.uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final count = snapshot.data!.length;
        if (count == 0) {
          return const Text('No achievements yet');
        }
        return Column(
          children: [
            Text(
              'Achievements',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.star, color: Colors.amber),
                const SizedBox(width: 4),
                Text('$count'),
              ],
            ),
          ],
        );
      },
    );
  }
}
