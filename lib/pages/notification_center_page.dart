import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../models/notification_preferences.dart';
import '../services/error_logger.dart';
import '../services/notification_service.dart';
import '../services/seasonal_challenge_service.dart';
import 'achievements_page.dart';
import 'friend_requests_page.dart';
import 'seasonal_challenges_page.dart';
import '../models/group.dart';
import '../services/group_service.dart';
import 'group_detail_page.dart';
import '../services/friend_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';

/// Page showing a list of notifications for the current user.
class NotificationCenterPage extends StatefulWidget {
  /// Service used to fetch and update notifications.
  final NotificationService service;

  /// Auth instance to identify the current user.
  final FirebaseAuth auth;

  /// Service used to trigger vibrations.
  final VibrationService vibrationService;

  /// Creates a [NotificationCenterPage].
  NotificationCenterPage({
    super.key,
    NotificationService? service,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
  })  : service = service ?? NotificationService(),
        auth = auth ?? FirebaseAuth.instance,
        vibrationService = vibrationService ?? const VibrationService();

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
    final bool showBack = Navigator.of(context).canPop();
    final actions = user == null
        ? null
        : <Widget>[
            IconButton(
              tooltip: 'Clear all',
              onPressed: (!_hasNotifications || _isClearing)
                  ? null
                  : _clearNotifications,
              icon: _isClearing
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.clear_all),
            ),
          ];
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        'Notifications',
        actions: actions,
        automaticallyImplyLeading: showBack,
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: user == null
            ? const Center(child: Text('Please sign in'))
            : StreamBuilder<List<AppNotification>>(
                stream:
                    widget.service.notifications(user.uid).asBroadcastStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final data = snapshot.data ?? [];
                  final hasNotifications = data.isNotEmpty;
                  if (hasNotifications != _hasNotifications) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) {
                        return;
                      }
                      setState(() => _hasNotifications = hasNotifications);
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
                        onTap: () {
                          final uid = widget.auth.currentUser?.uid;
                          if (uid != null) {
                            final messenger = ScaffoldMessenger.of(context);
                            setState(() => _readLocally.add(n.id));
                            unawaited(widget.service
                                .markRead(uid, n.id)
                                .catchError((e, st) {
                              ErrorLogger.log(e, st);
                              if (mounted) {
                                setState(() => _readLocally.remove(n.id));
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Failed to mark notification as read.',
                                    ),
                                  ),
                                );
                              }
                            }));
                          }
                          if (context.mounted) {
                            unawaited(_navigate(context, n));
                          }
                        },
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: _icon(n.type, read),
                          title: Text(_text(n)),
                          subtitle: n.message != null ? Text(n.message!) : null,
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }

  Widget _icon(NotificationType type, bool read) {
    final color = read ? Colors.grey : Colors.blue;
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
        // Navigate to the specific group’s detail page when possible.
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
          final group = Group.fromFirestore(snap);
          if (!context.mounted) return;
          unawaited(widget.vibrationService.lightImpact());
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GroupDetailPage(
                group: group,
                groupService: GroupService(firestore: widget.service.firestore),
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
