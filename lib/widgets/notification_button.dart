import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
import '../services/vibration_service.dart';
import '../pages/notification_center_page.dart';
import '../models/app_notification.dart';

class NotificationButton extends StatelessWidget {
  final NotificationService service;
  final FirebaseAuth auth;
  final VibrationService? vibrationService;

  const NotificationButton({
    super.key,
    required this.service,
    required this.auth,
    this.vibrationService,
  });

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<List<AppNotification>>(
      stream: service.notifications(user.uid),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data?.where((n) => !n.read).length ?? 0;

        return IconButton(
          icon: Stack(
            children: [
              const Icon(Icons.notifications),
              if (unreadCount > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    key: ValueKey(unreadCount),
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 8,
                      minHeight: 8,
                    ),
                  ),
                ),
            ],
          ),
          tooltip: 'Notifications',
          onPressed: () {
            if (vibrationService != null) {
              unawaited(vibrationService!.mediumImpact());
            }
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => NotificationCenterPage(
                  service: service,
                  auth: auth,
                  vibrationService:
                      vibrationService ?? const VibrationService(),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
