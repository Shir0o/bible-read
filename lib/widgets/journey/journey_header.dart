import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import '../common_styles.dart';
import '../../services/notification_service.dart';
import '../../services/vibration_service.dart';
import '../../pages/notification_center_page.dart';
import '../../models/app_notification.dart';

class JourneyHeader extends StatelessWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  const JourneyHeader({
    super.key,
    required this.auth,
    required this.firestore,
  });

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.hPadding,
        vertical: AppSpacing.vPadding,
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: ClipOval(
              child: user?.photoURL != null
                  ? Image.network(
                      user!.photoURL!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.person,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.person,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),

          // Greeting & Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Keep going,',
                  style: AppTextStyles.body.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  user?.displayName ?? 'Friend',
                  style: AppTextStyles.title.copyWith(
                    color: colorScheme.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Notification Button
          StreamBuilder<List<AppNotification>>(
            stream: user != null
                ? NotificationService(firestore: firestore)
                    .notifications(user.uid)
                : Stream.value([]),
            builder: (context, snapshot) {
              final unreadCount =
                  snapshot.data?.where((n) => !n.read).length ?? 0;

              return Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                  ),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: IconButton(
                        icon: Icon(
                          Icons.notifications_outlined,
                          color: colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        onPressed: () {
                          const VibrationService().lightImpact();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => NotificationCenterPage(
                                service:
                                    NotificationService(firestore: firestore),
                                auth: auth,
                                vibrationService: const VibrationService(),
                              ),
                            ),
                          );
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colorScheme.tertiary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.surfaceContainer,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
