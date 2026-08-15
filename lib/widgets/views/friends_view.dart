import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import '../../services/friend_service.dart';
import '../../services/vibration_service.dart';
import '../../theme/app_theme.dart';
import '../common_styles.dart';
import '../skeleton_loader.dart';
import '../skeletons/friends_skeleton.dart';
import '../../services/error_logger.dart';
import '../../pages/add_friend_page.dart';
import '../../pages/friend_requests_page.dart';
import '../nudge_sheet.dart';

/// Body of the Friends screen, matching the design: a friend-requests entry
/// card, a "Your circle" section with presence, and one row per friend with a
/// quiet action chip (Amen when they read, Nudge when they haven't).
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

class _FriendsViewState extends State<FriendsView>
    with AutomaticKeepAliveClientMixin {
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
  bool get wantKeepAlive => true;

  void _openAddFriend() {
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
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = widget.auth.currentUser;
    if (user == null) {
      return const Center(child: Text('Please sign in'));
    }

    return StreamBuilder<List<Friend>>(
      stream: widget.friendService.friends(user.uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Failed to load data');
        }
        return SkeletonLoader(
          loading: !snapshot.hasData,
          skeleton: const FriendsSkeleton(),
          child: snapshot.hasData
              ? _buildContent(context, user, snapshot.data!)
              : const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, User user, List<Friend> friends) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _buildRequestsCard(context, user),
        const SizedBox(height: 26),
        if (friends.isEmpty)
          _buildEmptyState(context)
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Your circle',
                  style: AppTextStyles.title(context).copyWith(fontSize: 19),
                ),
                Text(
                  '${friends.length} friend${friends.length == 1 ? '' : 's'}',
                  style: AppTextStyles.caption(context).copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildFriendsList(context, user, friends),
        ],
      ],
    );
  }

  Widget _buildRequestsCard(BuildContext context, User user) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);

    return StreamBuilder<List<FriendRequest>>(
      stream: widget.friendService.pendingRequests(user.uid),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;

        return CommonStyles.buildTappableCard(
          context: context,
          margin: EdgeInsets.zero,
          onTap: () {
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
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: appColors.accentSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.person_add_alt_1_outlined,
                  size: 21,
                  color: colorScheme.tertiary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Friend requests',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      count > 0
                          ? '$count waiting to connect'
                          : 'No pending requests',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onTertiary,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right,
                size: 19,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFriendsList(
    BuildContext context,
    User user,
    List<Friend> friends,
  ) {
    return StreamBuilder<Set<String>>(
      stream: widget.friendService.readTodayUids(
        uid: user.uid,
        friendUids: friends.map((f) => f.uid).toList(),
        date: DateTime.now(),
      ),
      builder: (context, snapshot) {
        final readToday = snapshot.data ?? <String>{};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final friend in friends)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _buildFriendRow(
                  context,
                  user,
                  friend,
                  read: readToday.contains(friend.uid),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildFriendRow(
    BuildContext context,
    User user,
    Friend friend, {
    required bool read,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = friend.name.isEmpty ? 'Friend' : friend.name;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final nudged = _nudgedToday.contains(friend.uid);

    return CommonStyles.buildCard(
      context: context,
      margin: EdgeInsets.zero,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primaryContainer,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  read ? 'Read today' : 'Not yet today',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: read
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.7,
                              ),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildActionChip(context, user, friend, read: read, nudged: nudged),
        ],
      ),
    );
  }

  Widget _buildActionChip(
    BuildContext context,
    User user,
    Friend friend, {
    required bool read,
    required bool nudged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);

    final Widget label;
    final VoidCallback? onTap;

    if (nudged) {
      label = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 13),
          SizedBox(width: 5),
          Text('Sent'),
        ],
      );
      onTap = () {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Encouragement already sent today')),
        );
      };
    } else if (read) {
      label = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 13),
          SizedBox(width: 5),
          Text('Amen'),
        ],
      );
      onTap = () => _sendAmen(context, user, friend);
    } else {
      label = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.waving_hand_outlined, size: 13),
          SizedBox(width: 5),
          Text('Nudge'),
        ],
      );
      onTap = () => _openNudgeSheet(context, user, friend);
    }

    return Material(
      color: nudged ? appColors.primarySoft : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(99),
        side: BorderSide(
          color: nudged ? appColors.primaryLine : appColors.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: DefaultTextStyle(
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color:
                  nudged ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            child: label,
          ),
        ),
      ),
    );
  }

  Future<void> _sendAmen(BuildContext context, User user, Friend friend) async {
    unawaited(widget.vibrationService.lightImpact());
    try {
      final result = await widget.friendService.nudgeFriend(
        currentUid: user.uid,
        friendUid: friend.uid,
        currentName: user.displayName ?? 'You',
      );
      if (!mounted || !context.mounted) return;
      if (result == NudgeResult.alreadySent) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Encouragement already sent today')),
        );
      } else if (result == NudgeResult.sent) {
        setState(() {
          _nudgedToday.add(friend.uid);
        });
      }
    } catch (e, st) {
      debugPrint('Failed to send encouragement: $e');
      ErrorLogger.log(e, st);
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.groups_outlined,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No friends yet',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Invite friends to track your reading journey together.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openAddFriend,
              icon: const Icon(Icons.person_add),
              label: const Text('Find Friends'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openNudgeSheet(
    BuildContext context,
    User user,
    Friend friend,
  ) async {
    unawaited(widget.vibrationService.lightImpact());
    await showNudgeSheet(
      context,
      person: NudgePerson(name: friend.name.isEmpty ? 'Friend' : friend.name),
      vibrationService: widget.vibrationService,
      onSend: (message) async {
        try {
          final result = await widget.friendService.nudgeFriend(
            currentUid: user.uid,
            friendUid: friend.uid,
            currentName: user.displayName ?? 'You',
          );
          if (mounted && result != NudgeResult.alreadySent) {
            setState(() {
              _nudgedToday.add(friend.uid);
            });
          }
          return result;
        } catch (e, st) {
          debugPrint('Failed to send encouragement: $e');
          ErrorLogger.log(e, st);
          rethrow;
        }
      },
    );
  }
}
