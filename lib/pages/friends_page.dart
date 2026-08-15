import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import '../services/friend_service.dart';
import '../services/vibration_service.dart';
import '../widgets/sub_header.dart';
import '../widgets/views/friends_view.dart';
import 'add_friend_page.dart';

/// Page that lists current friends and allows sending friend requests by email.
class FriendsPage extends StatelessWidget {
  /// Service used to manage friends and requests.
  final FriendService friendService;

  /// Firebase auth instance.
  final FirebaseAuth auth;

  /// Service used to trigger vibrations.
  final VibrationService vibrationService;

  /// Creates a [FriendsPage].
  FriendsPage({
    super.key,
    FriendService? friendService,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
  })  : friendService = friendService ?? FriendService(),
        auth = auth ?? FirebaseAuth.instance,
        vibrationService = vibrationService ?? const VibrationService();

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            SubHeader(
              title: 'Friends',
              onBack: () => Navigator.of(context).pop(),
              right: IconButton(
                icon: const Icon(Icons.person_add_alt_1_outlined),
                tooltip: 'Add friend',
                onPressed: () {
                  if (user == null) return;
                  unawaited(vibrationService.lightImpact());
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AddFriendPage(
                        friendService: friendService,
                        auth: auth,
                        vibrationService: vibrationService,
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: FriendsView(
                friendService: friendService,
                auth: auth,
                vibrationService: vibrationService,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
