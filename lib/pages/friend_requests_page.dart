import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import '../services/friend_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/friend_request_widget.dart';

/// Page that lists all pending friend requests for the current user.
class FriendRequestsPage extends StatelessWidget {
  /// Service used to load and respond to requests.
  final FriendService friendService;

  /// Auth instance to identify the current user.
  final FirebaseAuth auth;

  /// Service used to trigger vibrations.
  final VibrationService vibrationService;

  /// Creates a [FriendRequestsPage].
  FriendRequestsPage({
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
      appBar: CommonStyles.buildAppBar(
        context,
        'Friend Requests',
        leading: BackButton(onPressed: () {
          unawaited(vibrationService.lightImpact());
          Navigator.of(context).pop();
        }),
        automaticallyImplyLeading: true,
      ),
      body: Container(
        decoration:
            CommonStyles.backgroundDecoration(Theme.of(context).colorScheme),
        child: user == null
            ? const Center(child: Text('Please sign in'))
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: FriendRequestWidget(
                        service: friendService,
                        currentUid: user.uid,
                        currentName: user.displayName ?? 'Unknown',
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
