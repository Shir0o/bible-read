import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/friend_service.dart';
import '../widgets/add_friend_form.dart';
import '../widgets/common_styles.dart';

/// Page containing a form to send friend requests by email.
class AddFriendPage extends StatefulWidget {
  /// Service used to send friend requests.
  final FriendService friendService;

  /// Firebase auth instance.
  final FirebaseAuth auth;

  /// Creates an [AddFriendPage].
  AddFriendPage({
    super.key,
    FriendService? friendService,
    FirebaseAuth? auth,
  })  : friendService = friendService ?? FriendService(),
        auth = auth ?? FirebaseAuth.instance;

  @override
  State<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends State<AddFriendPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar('Add Friend'),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        padding: const EdgeInsets.all(16.0),
        child: AddFriendForm(
          friendService: widget.friendService,
          auth: widget.auth,
          onComplete: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
