import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import '../services/friend_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/views/friends_view.dart';
import 'friend_requests_page.dart';

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
  }) : friendService = friendService ?? FriendService(),
       auth = auth ?? FirebaseAuth.instance,
       vibrationService = vibrationService ?? const VibrationService();

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        context,
        'Friends',
        automaticallyImplyLeading: false,
        actions: [
          if (user != null)
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: 'Add friend',
              onPressed: () {
                unawaited(vibrationService.lightImpact());
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FriendRequestsPage(
                      friendService: friendService,
                      auth: auth,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: FriendsView(
        friendService: friendService,
        auth: auth,
        vibrationService: vibrationService,
      ),
    );
  }
}
