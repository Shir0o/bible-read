import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import '../../services/friend_service.dart';
import '../../services/vibration_service.dart';
import '../common_styles.dart';
import '../../services/error_logger.dart';
import '../../pages/add_friend_page.dart';
import '../../pages/friend_requests_page.dart'; // Needed for direct navigation or extraction

/// View that lists current friends, suitable for embedding in a TabBarView.
class FriendsView extends StatefulWidget {
  final FriendService friendService;
  final FirebaseAuth auth;
  final VibrationService vibrationService;

  const FriendsView({
    super.key,
    required this.friendService,
    required this.auth,
    required this.vibrationService,
  });

  @override
  State<FriendsView> createState() => _FriendsViewState();
}

class _FriendsViewState extends State<FriendsView> {
  final Set<String> _nudgedToday = <String>{};
  StreamSubscription<Set<String>>? _nudgeSub;

  @override
  void initState() {
    super.initState();
    final user = widget.auth.currentUser;
    if (user != null) {
      _nudgeSub = widget.friendService.nudgedToday(user.uid).listen((ids) {
        if (mounted) {
          setState(() {
            _nudgedToday
              ..clear()
              ..addAll(ids);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _nudgeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    return Scaffold(
      body: Container(
        decoration:
            CommonStyles.backgroundDecoration(Theme.of(context).colorScheme),
        child: user == null
            ? const Center(child: Text('Please sign in'))
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildSignedInContent(user),
              ),
      ),
      floatingActionButton: user == null
          ? null
          : FloatingActionButton(
              heroTag: 'friends-fab',
              onPressed: () {
                unawaited(widget.vibrationService.lightImpact());
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AddFriendPage(
                      friendService: widget.friendService,
                      auth: widget.auth,
                      vibrationService: widget.vibrationService,
                    ),
                  ),
                );
              },
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildSignedInContent(User user) {
    return StreamBuilder<List<Friend>>(
      stream: widget.friendService.friends(user.uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Failed to load data');
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
        final friends = snapshot.data!;
        if (friends.isEmpty) {
          return const Center(child: Text('No friends yet'));
        }
        return ListView(
          children: friends
              .map(
                (f) => CommonStyles.buildTappableCard(
                  context: context,
                  onTap: () {},
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          f.name.isEmpty ? 'Friend' : f.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: 16),
                      _buildNudgeButton(user, f),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildNudgeButton(User user, Friend friend) {
    final nudged = _nudgedToday.contains(friend.uid);
    return IconButton(
      icon: Icon(
        nudged ? Icons.notifications_off : Icons.notifications_active,
        color: nudged ? Colors.grey : null,
      ),
      onPressed: nudged
          ? null
          : () async {
              final messenger = ScaffoldMessenger.of(context);
              setState(() {
                _nudgedToday.add(friend.uid);
              });
              try {
                final result = await widget.friendService.nudgeFriend(
                  currentUid: user.uid,
                  friendUid: friend.uid,
                  currentName: user.displayName ?? 'You',
                );
                if (!mounted) return;
                switch (result) {
                  case NudgeResult.alreadyRead:
                    setState(() {
                      _nudgedToday.remove(friend.uid);
                    });
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Friend already read today'),
                      ),
                    );
                    break;
                  case NudgeResult.alreadySent:
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Nudge already sent'),
                      ),
                    );
                    break;
                  case NudgeResult.sent:
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Nudge sent'),
                      ),
                    );
                    break;
                }
              } catch (e, st) {
                debugPrint('Failed to send nudge: $e');
                ErrorLogger.log(e, st);
                if (!mounted) return;
                setState(() {
                  _nudgedToday.remove(friend.uid);
                });
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Failed to send nudge'),
                  ),
                );
              }
            },
    );
  }
}
