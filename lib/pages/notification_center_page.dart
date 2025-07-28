import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../models/notification_preferences.dart';
import '../services/notification_service.dart';
import 'achievements_page.dart';
import '../widgets/common_styles.dart';

/// Page showing a list of notifications for the current user.
class NotificationCenterPage extends StatelessWidget {
  /// Service used to fetch and update notifications.
  final NotificationService service;

  /// Auth instance to identify the current user.
  final FirebaseAuth auth;

  /// Creates a [NotificationCenterPage].
  NotificationCenterPage({
    super.key,
    NotificationService? service,
    FirebaseAuth? auth,
  })  : service = service ?? NotificationService(),
        auth = auth ?? FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    return Scaffold(
      appBar: CommonStyles.buildAppBar('Notifications'),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: user == null
            ? const Center(child: Text('Please sign in'))
            : StreamBuilder<List<AppNotification>>(
                stream: service.notifications(user.uid),
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
                      return ListTile(
                        leading: _icon(n.type, n.read),
                        title: Text(_text(n)),
                        subtitle: n.message != null ? Text(n.message!) : null,
                        onTap: () async {
                          final uid = auth.currentUser?.uid;
                          if (uid != null) {
                            await service.markRead(uid, n.id);
                          }
                          if (context.mounted) {
                            _navigate(context, n);
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
      case NotificationType.dailyReminder:
        return Icon(Icons.calendar_today, color: color);
      case NotificationType.comment:
        return Icon(Icons.comment, color: color);
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
      case NotificationType.dailyReminder:
        return 'Daily reading reminder';
      case NotificationType.comment:
        return 'New comment on your reading';
    }
  }

  void _navigate(BuildContext context, AppNotification n) {
    switch (n.type) {
      case NotificationType.achievement:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                AchievementsPage(auth: auth, firestore: service.firestore),
          ),
        );
        break;
      case NotificationType.like:
      case NotificationType.nudge:
      case NotificationType.signup:
      case NotificationType.friendRequest:
      case NotificationType.dailyReminder:
      case NotificationType.comment:
        break;
    }
  }
}
