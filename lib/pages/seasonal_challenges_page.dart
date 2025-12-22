import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/season.dart';
import '../models/seasonal_challenge.dart';
import '../services/seasonal_challenge_service.dart';
import '../widgets/common_styles.dart';

class SeasonalChallengesView extends StatelessWidget {
  final FirebaseAuth auth;
  final SeasonalChallengeService service;

  const SeasonalChallengesView({
    super.key,
    required this.auth,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) return const Center(child: Text('Please sign in'));

    return FutureBuilder<Season?>(
      future: service.fetchActiveSeason(),
      builder: (context, seasonSnapshot) {
        if (seasonSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final season = seasonSnapshot.data;
        if (season == null) {
          return const Center(child: Text('No active season currently.'));
        }

        return StreamBuilder<List<SeasonalChallenge>>(
          stream: service.streamChallenges(season.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final challenges = snapshot.data ?? [];
            if (challenges.isEmpty) {
              return const Center(child: Text('No active challenges at the moment.'));
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: challenges.length,
              itemBuilder: (context, index) {
                final challenge = challenges[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.eco),
                    title: Text(challenge.title),
                    subtitle: Text(challenge.description),
                    trailing: Text('${challenge.reward?.amount ?? 0} pts'),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// Wrapper
class SeasonalChallengesPage extends StatelessWidget {
  final FirebaseAuth auth;
  final SeasonalChallengeService service;

  const SeasonalChallengesPage({
    super.key,
    required this.auth,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar(context, 'Seasonal Challenges'),
      body: SeasonalChallengesView(auth: auth, service: service),
    );
  }
}
