import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/friend_streak_link.dart';
import '../services/error_logger.dart';
import '../services/friend_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import 'friend_requests_page.dart';

/// Page that allows inviting friends to start a streak.
class InviteStreakPage extends StatefulWidget {
  final FriendService friendService;
  final FirebaseAuth auth;
  final VibrationService vibrationService;

  InviteStreakPage({
    super.key,
    FriendService? friendService,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
  })  : friendService = friendService ?? FriendService(),
        auth = auth ?? FirebaseAuth.instance,
        vibrationService = vibrationService ?? const VibrationService();

  @override
  State<InviteStreakPage> createState() => _InviteStreakPageState();
}

class _InviteStreakPageState extends State<InviteStreakPage> {
  final Set<String> _sendingStreakInvites = <String>{};

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please sign in')));
    }

    return Scaffold(
      appBar: CommonStyles.buildAppBar(context, 'Start a streak'),
      body: Container(
        decoration:
            CommonStyles.backgroundDecoration(Theme.of(context).colorScheme),
        child: StreamBuilder<List<FriendStreakLink>>(
          stream: widget.friendService.activeStreakLinks(user.uid),
          builder: (context, activeSnapshot) {
            if (activeSnapshot.hasError) {
              return const Center(child: Text('Failed to load streak data'));
            }
            if (!activeSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return StreamBuilder<List<FriendStreakLink>>(
              stream: widget.friendService.pendingStreakInvites(user.uid),
              builder: (context, pendingSnapshot) {
                if (pendingSnapshot.hasError) {
                  return const Center(
                      child: Text('Failed to load streak data'));
                }
                if (!pendingSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final activeLinks = activeSnapshot.data!;
                final pendingInvites = pendingSnapshot.data!;
                final reachedLimit =
                    activeLinks.length >= FriendService.maxActiveStreakLinks;

                return Column(
                  children: [
                    _buildLimitCard(activeLinks.length, reachedLimit),
                    const SizedBox(height: 16),
                    Expanded(
                      child: StreamBuilder<List<Friend>>(
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

                          final activeMap = {
                            for (final link in activeLinks)
                              link.partnerUid: link
                          };
                          final pendingMap = {
                            for (final link in pendingInvites)
                              link.partnerUid: link
                          };

                          // Filter out friends who are already in an active streak
                          // or have a pending invite (unless it's incoming, then we show "Respond")
                          // Actually, let's show all friends but change the action button state
                          // to be consistent with how it was in FriendsPage, but focused on Streaks.

                          return ListView(
                            children: friends
                                .map(
                                  (f) => _buildFriendTile(
                                    user,
                                    f,
                                    activeMap,
                                    pendingMap,
                                    reachedLimit,
                                  ),
                                )
                                .toList(),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildLimitCard(int activeCount, bool reachedLimit) {
    return CommonStyles.buildCard(
      context: context,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          reachedLimit ? Icons.warning_amber : Icons.local_fire_department,
          color: reachedLimit ? Colors.orange : Colors.pink,
        ),
        title: Text(
          'Streak links: $activeCount / ${FriendService.maxActiveStreakLinks}',
        ),
        subtitle: Text(
          reachedLimit
              ? 'You\'ve hit the streak cap. Remove a link before inviting more friends.'
              : 'Invite friends to start a streak together.',
        ),
      ),
    );
  }

  Widget _buildFriendTile(
    User user,
    Friend friend,
    Map<String, FriendStreakLink> activeLinks,
    Map<String, FriendStreakLink> pendingLinks,
    bool reachedLimit,
  ) {
    return CommonStyles.buildTappableCard(
      context: context,
      onTap: () {},
      child: Row(
        children: [
          Expanded(
            child: Text(
              friend.name.isEmpty ? 'Friend' : friend.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: 16),
          _buildStreakAction(
            user,
            friend,
            activeLinks,
            pendingLinks,
            reachedLimit,
          ),
        ],
      ),
    );
  }

  Widget _buildStreakAction(
    User user,
    Friend friend,
    Map<String, FriendStreakLink> activeLinks,
    Map<String, FriendStreakLink> pendingLinks,
    bool reachedLimit,
  ) {
    final pending = pendingLinks[friend.uid];
    final isSending = _sendingStreakInvites.contains(friend.uid);

    if (activeLinks.containsKey(friend.uid)) {
      return const Chip(label: Text('Streak active'));
    }

    if (pending != null) {
      if (pending.isIncoming) {
        return FilledButton.tonal(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FriendRequestsPage(
                  friendService: widget.friendService,
                  auth: widget.auth,
                ),
              ),
            );
          },
          child: const Text('Respond'),
        );
      } else {
        return Text(
          'Invite pending',
          key: Key('streakInvitePendingLabel_${friend.uid}'),
        );
      }
    }

    final disabled = reachedLimit || isSending;
    return FilledButton(
      key: Key('streakInviteButton_${friend.uid}'),
      onPressed: disabled ? null : () => _startStreakInvite(friend),
      child: const Text('Start streak'),
    );
  }

  Future<void> _startStreakInvite(Friend friend) async {
    final user = widget.auth.currentUser;
    if (user == null || _sendingStreakInvites.contains(friend.uid)) {
      return;
    }
    setState(() {
      _sendingStreakInvites.add(friend.uid);
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.friendService.sendStreakInvite(
        fromUid: user.uid,
        fromName: user.displayName ?? 'You',
        toUid: friend.uid,
        toName: friend.name,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
            content: Text(
                'Invite sent to ${friend.name.isEmpty ? 'friend' : friend.name}')),
      );
    } on StreakLinkLimitReachedException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e, st) {
      debugPrint('Failed to send streak invite: $e');
      ErrorLogger.log(e, st);
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to send streak invite')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sendingStreakInvites.remove(friend.uid);
        });
      } else {
        _sendingStreakInvites.remove(friend.uid);
      }
    }
  }
}
