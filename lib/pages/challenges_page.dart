import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/friend_service.dart';
import '../services/vibration_service.dart';
import '../widgets/sub_header.dart';
import '../services/seasonal_challenge_service.dart';

import 'seasonal_challenges_page.dart';

class ChallengesPage extends StatelessWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FriendService friendService;
  final VibrationService vibrationService;

  const ChallengesPage({
    super.key,
    required this.auth,
    required this.firestore,
    required this.friendService,
    required this.vibrationService,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            SubHeader(
              title: 'Challenges',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: SeasonalChallengesView(
                auth: auth,
                service: SeasonalChallengeService(firestore: firestore),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
