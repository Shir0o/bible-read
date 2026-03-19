import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../models/notification_preferences.dart';
import '../services/error_logger.dart';
import '../services/notification_service.dart';
import '../services/seasonal_challenge_service.dart';
import '../services/vibration_service.dart';
import '../services/group_service.dart';
import '../services/friend_service.dart';
import 'friend_requests_page.dart';
import 'seasonal_challenges_page.dart';
import 'group_join_requests_page.dart';

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
  bool _markingAllRead = false;

  Future<void> _markAllAsRead() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null || _markingAllRead) return;

    setState(() => _markingAllRead = true);
    try {
      unawaited(widget.vibrationService.mediumImpact());
      await widget.service.markAllRead(uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All notifications marked as read')),
        );
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to mark all as read')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _markingAllRead = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: Text(
          'Notifications',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: TextButton(
              onPressed: _markingAllRead ? null : _markAllAsRead,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.primary,
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
                backgroundColor:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: _markingAllRead
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    )
                  : const Text('Mark all as read'),
            ),
          ),
        ],
      ),
      body: user == null
          ? const Center(child: Text('Please sign in'))
          : StreamBuilder<List<AppNotification>>(
              stream: widget.service.notifications(user.uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                      child: Text('Error loading notifications'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final notifications = snapshot.data!;
                if (notifications.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_none_outlined,
                          size: 64,
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No notifications yet',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Group notifications
                final newNotifications = <AppNotification>[];
                final earlierNotifications = <AppNotification>[];

                final now = DateTime.now();
                final oneWeekAgo = now.subtract(const Duration(days: 7));

                for (final n in notifications) {
                  if (!n.read) {
                    newNotifications.add(n);
                  } else if (n.timestamp.isAfter(oneWeekAgo)) {
                    earlierNotifications.add(n);
                  }
                }

                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (newNotifications.isNotEmpty) ...[
                      _buildSectionHeader(context, 'New'),
                      ...newNotifications.map((n) => _NotificationItem(
                            key: ValueKey(n.id),
                            notification: n,
                            service: widget.service,
                            auth: widget.auth,
                            vibrationService: widget.vibrationService,
                          )),
                    ],
                    if (earlierNotifications.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildSectionHeader(context, 'Earlier this week'),
                      ...earlierNotifications.map((n) => _NotificationItem(
                            key: ValueKey(n.id),
                            notification: n,
                            service: widget.service,
                            auth: widget.auth,
                            vibrationService: widget.vibrationService,
                          )),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

class _NotificationItem extends StatefulWidget {
  final AppNotification notification;
  final NotificationService service;
  final FirebaseAuth auth;
  final VibrationService vibrationService;

  const _NotificationItem({
    super.key,
    required this.notification,
    required this.service,
    required this.auth,
    required this.vibrationService,
  });

  @override
  State<_NotificationItem> createState() => _NotificationItemState();
}

class _NotificationItemState extends State<_NotificationItem> {
  late Future<DocumentSnapshot> _userFuture;

  @override
  void initState() {
    super.initState();
    if (widget.notification.fromUid != null) {
      _userFuture = widget.service.firestore
          .collection('users')
          .doc(widget.notification.fromUid)
          .get();
    }
  }

  @override
  void didUpdateWidget(_NotificationItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.notification.fromUid != oldWidget.notification.fromUid) {
      if (widget.notification.fromUid != null) {
        _userFuture = widget.service.firestore
            .collection('users')
            .doc(widget.notification.fromUid)
            .get();
      }
    }
  }

  Future<void> _handleTap(BuildContext context) async {
    if (!widget.notification.read) {
      // Mark as read
      try {
        await widget.service
            .markRead(widget.auth.currentUser!.uid, widget.notification.id);
      } catch (e) {
        // Ignore error
      }
    }

    if (!context.mounted) return;
    unawaited(widget.vibrationService.lightImpact());
    await _navigate(context);
  }

  Future<void> _navigate(BuildContext context) async {
    switch (widget.notification.type) {
      case NotificationType.friendRequest:
        final friendService = FriendService(
          firestore: widget.service.firestore,
          notificationService: widget.service,
        );
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
      case NotificationType.groupJoinRequest:
        if (widget.notification.groupId != null) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GroupJoinRequestsPage(
                groupId: widget.notification.groupId!,
                groupService: GroupService(
                  firestore: widget.service.firestore,
                  notificationService: widget.service,
                ),
                auth: widget.auth,
              ),
            ),
          );
        }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isUnread = !widget.notification.read;

    return Material(
      color: isUnread
          ? colorScheme.surfaceContainerHigh.withValues(alpha: 0.5)
          : Colors.transparent,
      child: InkWell(
        onTap: () => _handleTap(context),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvatar(context),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMessage(context),
                    const SizedBox(height: 4),
                    Text(
                      _timeAgo(widget.notification.timestamp),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread)
                Container(
                  margin: const EdgeInsets.only(top: 8, left: 8),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget avatarContent;
    if (widget.notification.fromUid != null) {
      avatarContent = FutureBuilder<DocumentSnapshot>(
        future: _userFuture,
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>?;
            final photoUrl = data?['photoUrl'] as String?;
            final name = data?['name'] as String?;

            if (photoUrl != null) {
              return CachedNetworkImage(
                imageUrl: photoUrl,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => _buildInitials(name),
              );
            } else {
              return _buildInitials(name);
            }
          }
          return const Icon(Icons.person, size: 20);
        },
      );
    } else {
      avatarContent = _buildSystemIcon(context);
    }

    return Stack(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.surfaceContainerHighest,
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Center(child: avatarContent),
        ),
        Positioned(
          bottom: -2,
          right: -2,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _getBadgeColor(context),
              shape: BoxShape.circle,
              border: Border.all(color: colorScheme.surface, width: 2),
            ),
            child: Icon(
              _getBadgeIcon(),
              size: 10,
              color: _getBadgeIconColor(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInitials(String? name) {
    if (name == null || name.isEmpty) return const Icon(Icons.person, size: 20);
    return Text(
      name[0].toUpperCase(),
      style: const TextStyle(fontWeight: FontWeight.bold),
    );
  }

  Widget _buildSystemIcon(BuildContext context) {
    IconData icon;
    switch (widget.notification.type) {
      case NotificationType.seasonalChallenge:
        icon = Icons.eco;
        break;
      case NotificationType.groupScheduleUpdate:
        icon = Icons.calendar_today;
        break;
      default:
        icon = Icons.notifications;
    }
    return Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant);
  }

  IconData _getBadgeIcon() {
    switch (widget.notification.type) {
      case NotificationType.like:
        return Icons.favorite;
      case NotificationType.comment:
        return Icons.chat_bubble;
      case NotificationType.friendRequest:
      case NotificationType.groupJoinRequest:
      case NotificationType.signup:
        return Icons.person_add;
      case NotificationType.nudge:
        return Icons.notifications_active;
      case NotificationType.groupScheduleUpdate:
        return Icons.calendar_today;
      case NotificationType.seasonalChallenge:
        return Icons.eco;
      default:
        return Icons.notifications;
    }
  }

  Color _getBadgeColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (widget.notification.type) {
      case NotificationType.like:
      case NotificationType.comment:
        return colorScheme.tertiary;
      case NotificationType.friendRequest:
      case NotificationType.groupJoinRequest:
        return colorScheme.primary;
      case NotificationType.seasonalChallenge:
        return colorScheme.secondary;
      default:
        return colorScheme.surfaceContainerHighest;
    }
  }

  Color _getBadgeIconColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (widget.notification.type) {
      case NotificationType.like:
      case NotificationType.comment:
        return colorScheme.onTertiary;
      case NotificationType.friendRequest:
      case NotificationType.groupJoinRequest:
        return colorScheme.onPrimary;
      case NotificationType.seasonalChallenge:
        return colorScheme.onSecondary;
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  Widget _buildMessage(BuildContext context) {
    String text = widget.notification.message ?? _getDefaultMessage();

    if (widget.notification.fromUid != null) {
      return FutureBuilder<DocumentSnapshot>(
        future: _userFuture,
        builder: (context, snapshot) {
          String displayName = 'Someone';
          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>?;
            displayName = data?['name'] as String? ?? 'Someone';
          }

          return RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: _buildTextSpans(context, displayName, text),
            ),
          );
        },
      );
    }

    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }

  List<InlineSpan> _buildTextSpans(
      BuildContext context, String name, String rawMessage) {
    final colorScheme = Theme.of(context).colorScheme;
    final boldStyle =
        TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface);

    if (rawMessage.startsWith(name)) {
      return [
        TextSpan(text: name, style: boldStyle),
        TextSpan(text: rawMessage.substring(name.length)),
      ];
    }

    if (widget.notification.message == null) {
      switch (widget.notification.type) {
        case NotificationType.like:
          return [
            TextSpan(text: name, style: boldStyle),
            const TextSpan(text: ' liked your progress'),
          ];
        case NotificationType.comment:
          return [
            TextSpan(text: name, style: boldStyle),
            const TextSpan(text: ' commented on your reading'),
          ];
        case NotificationType.friendRequest:
          return [
            TextSpan(text: name, style: boldStyle),
            const TextSpan(text: ' sent you a friend request'),
          ];
        case NotificationType.nudge:
          return [
            TextSpan(text: name, style: boldStyle),
            const TextSpan(text: ' nudged you to read'),
          ];
        default:
          break;
      }
    }

    return [TextSpan(text: rawMessage)];
  }

  String _getDefaultMessage() {
    switch (widget.notification.type) {
      case NotificationType.seasonalChallenge:
        return 'Seasonal challenge update';
      case NotificationType.groupScheduleUpdate:
        return 'Group schedule updated';
      case NotificationType.groupJoinRequest:
        return 'New group join request';
      default:
        return 'New notification';
    }
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}
