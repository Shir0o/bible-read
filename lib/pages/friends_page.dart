import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import '../models/friend_streak_link.dart';
import '../services/friend_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../services/error_logger.dart';
import 'add_friend_page.dart';
import 'friend_requests_page.dart';

/// Page that lists current friends and allows sending friend requests by email.
class FriendsPage extends StatefulWidget {
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
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  /// Tracks friends nudged today so the button can be disabled.
  final Set<String> _nudgedToday = <String>{};

  /// Tracks streak invites currently being sent so the button can be disabled.
  final Set<String> _sendingStreakInvites = <String>{};

  /// Subscription to the nudged today stream.
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
      appBar: CommonStyles.buildAppBar(
        'Friends',
        automaticallyImplyLeading: false,
        actions: [
          if (user != null)
            IconButton(
              icon: const Icon(Icons.person_add),
              onPressed: () {
                unawaited(widget.vibrationService.lightImpact());
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FriendRequestsPage(
                      friendService: widget.friendService,
                      auth: widget.auth,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
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
    return StreamBuilder<List<FriendStreakLink>>(
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
              return const Center(child: Text('Failed to load streak data'));
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
                        for (final link in activeLinks) link.partnerUid: link
                      };
                      final pendingMap = {
                        for (final link in pendingInvites) link.partnerUid: link
                      };
                      return ListView(
                        children: friends
                            .map(
                              (f) => CommonStyles.buildTappableCard(
                                onTap: () {},
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            f.name.isEmpty ? 'Friend' : f.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Send nudges or start a streak together.',
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    SizedBox(
                                      width: 160,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          _buildNudgeButton(user, f),
                                          const SizedBox(height: 8),
                                          _buildStreakAction(
                                            user,
                                            f,
                                            activeMap,
                                            pendingMap,
                                            reachedLimit,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
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
    );
  }

  Widget _buildLimitCard(int activeCount, bool reachedLimit) {
    return Card(
      child: ListTile(
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

  Widget _buildStreakAction(
    User user,
    Friend friend,
    Map<String, FriendStreakLink> activeLinks,
    Map<String, FriendStreakLink> pendingLinks,
    bool reachedLimit,
  ) {
    final pending = pendingLinks[friend.uid];
    final isSending = _sendingStreakInvites.contains(friend.uid);
    final Widget child;
    if (activeLinks.containsKey(friend.uid)) {
      child = const Chip(label: Text('Streak active'));
    } else if (pending != null) {
      if (pending.isIncoming) {
        child = FilledButton.tonal(
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
        child = Text(
          'Invite pending',
          key: Key('streakInvitePendingLabel_${friend.uid}'),
        );
      }
    } else {
      final disabled = reachedLimit || isSending;
      child = FilledButton(
        key: Key('streakInviteButton_${friend.uid}'),
        onPressed: disabled ? null : () => _startStreakInvite(friend),
        child: const Text('Start streak'),
      );
    }

    return SizedBox(
      width: 160,
      child: Align(
        alignment: Alignment.centerRight,
        child: child,
      ),
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
