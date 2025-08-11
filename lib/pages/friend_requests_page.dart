import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/friend_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/friend_request_widget.dart';
import '../widgets/menu_button.dart';

/// Page that lists all pending friend requests for the current user.
class FriendRequestsPage extends StatelessWidget {
  /// Service used to load and respond to requests.
  final FriendService friendService;

  /// Auth instance to identify the current user.
  final FirebaseAuth auth;

  /// Creates a [FriendRequestsPage].
  FriendRequestsPage({
    super.key,
    FriendService? friendService,
    FirebaseAuth? auth,
  })  : friendService = friendService ?? FriendService(),
        auth = auth ?? FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        'Friend Requests',
        leading: const MenuButton(),
        automaticallyImplyLeading: false,
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: user == null
            ? const Center(child: Text('Please sign in'))
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: FriendRequestWidget(
                    service: friendService,
                    currentUid: user.uid,
                    currentName: user.displayName ?? 'Unknown',
                  ),
                ),
              ),
      ),
    );
  }
}
