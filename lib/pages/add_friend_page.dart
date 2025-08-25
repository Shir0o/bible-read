import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/friend_service.dart';
import '../widgets/add_friend_form.dart';
import '../widgets/common_styles.dart';
import '../services/vibration_service.dart';

/// Page containing a form to send friend requests by email.
class AddFriendPage extends StatefulWidget {
  /// Service used to send friend requests.
  final FriendService friendService;

  /// Firebase auth instance.
  final FirebaseAuth auth;

  /// Service used to trigger vibrations.
  final VibrationService vibrationService;

  /// Creates an [AddFriendPage].
  AddFriendPage({
    super.key,
    FriendService? friendService,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
  })  : friendService = friendService ?? FriendService(),
        auth = auth ?? FirebaseAuth.instance,
        vibrationService = vibrationService ?? const VibrationService();

  @override
  State<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends State<AddFriendPage> {
  VibrationService get vibrationService => widget.vibrationService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar('Add Friend'),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: AddFriendForm(
            friendService: widget.friendService,
            auth: widget.auth,
            onComplete: () {
              unawaited(vibrationService.mediumImpact());
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
    );
  }
}
