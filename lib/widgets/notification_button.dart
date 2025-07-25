import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../services/notification_service.dart';
import '../pages/notification_center_page.dart';

/// Icon button that navigates to [NotificationCenterPage] and shows the
/// number of unread notifications as a badge.
class NotificationButton extends StatelessWidget {
  /// Service used to read notifications.
  final NotificationService service;

  /// Firebase auth instance.
  final FirebaseAuth auth;

  /// Creates a [NotificationButton].
  NotificationButton({
    super.key,
    NotificationService? service,
    FirebaseAuth? auth,
  })  : service = service ?? NotificationService(),
        auth = auth ?? FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<AppNotification>>(
      stream: service.notifications(user.uid),
      builder: (context, snapshot) {
        final notifications = snapshot.data ?? [];
        final count = notifications.where((n) => !n.read).length;
        return IconButton(
          tooltip: 'Notifications',
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications),
              if (count > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) => AnimatedScale(
                      scale: animation.value,
                      duration: Duration.zero,
                      child: child,
                    ),
                    child: Container(
                      key: ValueKey<int>(count),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => NotificationCenterPage(
                  service: service,
                  auth: auth,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
