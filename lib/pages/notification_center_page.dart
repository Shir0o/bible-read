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

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    return Scaffold(
      appBar: CommonStyles.buildAppBar('Notifications'),
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
                  if (data.isEmpty) {
                    return const Center(child: Text('No notifications'));
                  }
                  return ListView.builder(
                    itemCount: data.length,
                    itemBuilder: (context, index) {
                      final n = data[index];
                      final read = n.read || _readLocally.contains(n.id);
                      return ListTile(
                        leading: _icon(n.type, read),
                        title: Text(_text(n)),
                        subtitle: n.message != null ? Text(n.message!) : null,
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
        return 'You received a friend request';
      case NotificationType.comment:
        return 'New comment on your reading';
      case NotificationType.groupJoinRequest:
        return 'You received a group join request';
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
        final uid = widget.auth.currentUser?.uid;
        if (uid == null) break;
        final messenger = ScaffoldMessenger.of(context);
        final friendService = FriendService(
          firestore: widget.service.firestore,
          notificationService: widget.service,
        );
        try {
          final requests = await friendService.pendingRequests(uid).first;
          if (requests.isEmpty) {
            try {
              await widget.service.markRead(uid, n.id);
            } catch (e, st) {
              ErrorLogger.log(e, st);
            }
            if (context.mounted) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('No pending friend requests'),
                ),
              );
            }
            break;
          }
        } catch (e, st) {
          ErrorLogger.log(e, st);
          break;
        }
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
      case NotificationType.groupJoinRequest:
      case NotificationType.groupScheduleUpdate:
        break;
    }
  }
}
