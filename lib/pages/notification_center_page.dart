import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/app_notification.dart';
import '../../models/notification_preferences.dart';
import '../../services/error_logger.dart';
import '../../services/notification_service.dart';
import '../../services/seasonal_challenge_service.dart';
import '../../pages/achievements_page.dart';
import '../../pages/friend_requests_page.dart';
import '../../pages/seasonal_challenges_page.dart';
import '../../services/group_service.dart';
import '../../pages/group_join_requests_page.dart';
import '../../services/friend_service.dart';
import '../../services/vibration_service.dart';
import '../widgets/common_styles.dart';

class NotificationCenterPage extends StatefulWidget {
  final NotificationService service;
  final FirebaseAuth auth;
  final VibrationService vibrationService;

  const NotificationCenterPage({
    super.key,
    required this.service,
    required this.auth,
    required this.vibrationService,
  });

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  final _readLocally = <String>{};
  bool _isClearing = false;
  bool _hasNotifications = false;

  Future<void> _clearNotifications() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null || _isClearing || !_hasNotifications) {
      return;
    }

    setState(() => _isClearing = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      unawaited(widget.vibrationService.mediumImpact());
      await widget.service.clearNotifications(uid);
      if (!mounted) {
        return;
      }
      setState(() {
        _readLocally.clear();
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Notifications cleared')),
      );
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to clear notifications')),
      );
    } finally {
      if (mounted) {
        setState(() => _isClearing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;

    // We wrap content in Scaffold to ensure ScaffoldMessenger works correctly
    // when this page is used standalone or in tests that expect a Scaffold.
    // However, if embedded in a TabBarView inside a Scaffold, nested Scaffold is okay.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration:
            CommonStyles.backgroundDecoration(Theme.of(context).colorScheme),
        child: user == null
            ? const Center(child: Text('Please sign in'))
            : Column(
                children: [
                  if (_hasNotifications)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: TextButton.icon(
                          onPressed: _isClearing ? null : _clearNotifications,
                          icon: _isClearing
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.clear_all, size: 18),
                          label: const Text('Clear All'),
                        ),
                      ),
                    ),
                  Expanded(
                    child: StreamBuilder<List<AppNotification>>(
                      stream: widget.service
                          .notifications(user.uid)
                          .asBroadcastStream(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final data = snapshot.data ?? [];
                        final hasNotifications = data.isNotEmpty;
                        if (hasNotifications != _hasNotifications) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) {
                              return;
                            }
                            setState(
                                () => _hasNotifications = hasNotifications);
                          });
                        }
                        if (data.isEmpty) {
                          return const Center(child: Text('No notifications'));
                        }
                        return ListView.builder(
                          itemCount: data.length,
                          itemBuilder: (context, index) {
                            final n = data[index];
                            final read = n.read || _readLocally.contains(n.id);
                            return CommonStyles.buildTappableCard(
                              context: context,
                              onTap: () {
                                final uid = widget.auth.currentUser?.uid;
                                if (uid != null) {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  setState(() => _readLocally.add(n.id));
                                  unawaited(
                                    widget.service
                                        .markRead(uid, n.id)
                                        .catchError((
                                      e,
                                      st,
                                    ) {
                                      ErrorLogger.log(e, st);
                                      if (mounted) {
                                        setState(
                                            () => _readLocally.remove(n.id));
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Failed to mark notification as read.',
                                            ),
                                          ),
                                        );
                                      }
                                    }),
                                  );
                                }
                                if (context.mounted) {
                                  unawaited(_navigate(context, n));
                                }
                              },
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: _icon(n.type, read),
                                title: Text(_text(n)),
                                subtitle:
                                    n.message != null ? Text(n.message!) : null,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _icon(NotificationType type, bool read) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = read ? colorScheme.onSurfaceVariant : colorScheme.primary;
    switch (type) {
      case NotificationType.like:
        return Icon(Icons.thumb_up, color: color);
      case NotificationType.nudge:
        return Icon(Icons.notifications_active, color: color);
      case NotificationType.signup:
        return Icon(Icons.person_add, color: color);
      case NotificationType.achievement:
        return Icon(Icons.emoji_events, color: color);
      case NotificationType.friendRequest:
        return Icon(Icons.person_add_alt, color: color);
      case NotificationType.comment:
        return Icon(Icons.comment, color: color);
      case NotificationType.groupJoinRequest:
        return Icon(Icons.group_add, color: color);
      case NotificationType.groupScheduleUpdate:
        return Icon(Icons.schedule, color: color);
      case NotificationType.seasonalChallenge:
        return Icon(Icons.eco, color: color);
    }
  }

  String _text(AppNotification n) {
    switch (n.type) {
      case NotificationType.like:
        return 'Someone liked your reading';
      case NotificationType.nudge:
        return 'You were nudged to read';
      case NotificationType.signup:
        return 'New signup';
      case NotificationType.achievement:
        return 'Achievement unlocked';
      case NotificationType.friendRequest:
        return n.message?.isNotEmpty == true
            ? n.message!
            : 'You received a friend request';
      case NotificationType.comment:
        return 'New comment on your reading';
      case NotificationType.groupJoinRequest:
        return n.message?.isNotEmpty == true
            ? n.message!
            : 'You received a group join request';
      case NotificationType.groupScheduleUpdate:
        return 'Group schedule updated';
      case NotificationType.seasonalChallenge:
        return 'Seasonal challenge reward ready';
    }
  }

  Future<void> _navigate(BuildContext context, AppNotification n) async {
    switch (n.type) {
      case NotificationType.achievement:
        if (!context.mounted) return;
        unawaited(widget.vibrationService.lightImpact());
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AchievementsPage(
              auth: widget.auth,
              firestore: widget.service.firestore,
            ),
          ),
        );
        break;
      case NotificationType.friendRequest:
        final friendService = FriendService(
          firestore: widget.service.firestore,
          notificationService: widget.service,
        );
        if (!context.mounted) return;
        unawaited(widget.vibrationService.lightImpact());
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FriendRequestsPage(
              auth: widget.auth,
              friendService: friendService,
            ),
          ),
        );
        break;
      case NotificationType.seasonalChallenge:
        if (!context.mounted) return;
        unawaited(widget.vibrationService.lightImpact());
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SeasonalChallengesPage(
              auth: widget.auth,
              service: SeasonalChallengeService(
                firestore: widget.service.firestore,
              ),
            ),
          ),
        );
        break;
      case NotificationType.like:
      case NotificationType.nudge:
      case NotificationType.signup:
      case NotificationType.comment:
      case NotificationType.groupScheduleUpdate:
        break;
      case NotificationType.groupJoinRequest:
        try {
          final gid = n.groupId;
          if (gid == null) {
            final messenger = ScaffoldMessenger.of(context);
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Open the group to manage join requests.'),
              ),
            );
            break;
          }
          final snap = await widget.service.firestore
              .collection('groups')
              .doc(gid)
              .get();
          if (!context.mounted) return;
          if (!snap.exists) {
            final messenger = ScaffoldMessenger.of(context);
            messenger.showSnackBar(
              const SnackBar(content: Text('Group not found')),
            );
            break;
          }
          if (!context.mounted) return;
          unawaited(widget.vibrationService.lightImpact());
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GroupJoinRequestsPage(
                groupId: gid,
                groupService: GroupService(
                  firestore: widget.service.firestore,
                  notificationService: widget.service,
                ),
                auth: widget.auth,
              ),
            ),
          );
        } catch (e, st) {
          ErrorLogger.log(e, st);
        }
        break;
    }
  }
}
