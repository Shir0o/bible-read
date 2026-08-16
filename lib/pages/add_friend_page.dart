import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/friend_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/add_friend_form.dart';
import '../widgets/sub_header.dart';

/// Page for sending a friend request by email, matching the design's
/// `AddFriendScreen`: a centered invitation intro, a bordered email field, and
/// a "Send invitation" action.
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
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            SubHeader(
              title: 'Add a friend',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.person_add_alt_1_outlined,
                          size: 30,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Invite someone to read with you',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTheme.fontSerif,
                        fontSize: 19,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'We\u2019ll send a gentle invitation by email. '
                      'No pressure \u2014 they can join whenever they\u2019re ready.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTheme.fontUi,
                        fontSize: 13.5,
                        height: 1.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 26),
                    AddFriendForm(
                      friendService: widget.friendService,
                      auth: widget.auth,
                      vibrationService: widget.vibrationService,
                      onComplete: () {
                        unawaited(widget.vibrationService.mediumImpact());
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
