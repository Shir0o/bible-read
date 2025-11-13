import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/friend_streak_link.dart';
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
    final user = widget.auth.currentUser;
    return Scaffold(
      appBar: CommonStyles.buildAppBar('Add Friend'),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (user != null)
                  StreamBuilder<List<FriendStreakLink>>(
                    stream: widget.friendService.activeStreakLinks(user.uid),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Text('Failed to load streak info');
                      }
                      if (!snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: LinearProgressIndicator(),
                        );
                      }
                      final activeLinks = snapshot.data!;
                      final reachedLimit = activeLinks.length >=
                          FriendService.maxActiveStreakLinks;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Streak links: '
                                '${activeLinks.length}/${FriendService.maxActiveStreakLinks}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                reachedLimit
                                    ? 'You\'ve reached the limit of streak partners. Complete or end a streak before inviting more friends.'
                                    : 'You can keep up to ${FriendService.maxActiveStreakLinks} streak partners at a time.',
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 16),
                AddFriendForm(
                  friendService: widget.friendService,
                  auth: widget.auth,
                  vibrationService: widget.vibrationService,
                  onComplete: () {
                    unawaited(vibrationService.mediumImpact());
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
