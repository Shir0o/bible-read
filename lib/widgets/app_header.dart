import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../pages/notification_center_page.dart';
import '../services/notification_service.dart';
import '../services/vibration_service.dart';
import 'common_styles.dart';
import 'navigation_menu_scope.dart';

/// Page top bar matching the design's `TopBar`: a small dim eyebrow, a serif
/// title, and right-hand actions (notification bell + avatar opening the menu).
class AppHeader extends StatelessWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final VibrationService vibrationService;
  final DateTime Function() dateProvider;
  final String eyebrow;
  final String title;
  final bool showProfileIcon;
  final bool showNotificationBell;

  const AppHeader({
    super.key,
    required this.auth,
    required this.firestore,
    required this.vibrationService,
    required this.dateProvider,
    required this.eyebrow,
    required this.title,
    this.showProfileIcon = true,
    this.showNotificationBell = true,
  });

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    final colorScheme = Theme.of(context).colorScheme;
    final initial = user != null && (user.displayName ?? '').isNotEmpty
        ? user.displayName![0].toUpperCase()
        : '?';

    return Container(
      constraints: const BoxConstraints(minHeight: 80),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  eyebrow,
                  style: AppTextStyles.caption(context).copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title(context).copyWith(
                    fontSize: 27,
                    fontWeight: FontWeight.w500,
                    height: 1.05,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (showNotificationBell) ...[
            const SizedBox(width: 12),
            StreamBuilder<List<AppNotification>>(
              stream: user != null
                  ? NotificationService(
                      firestore: firestore,
                    ).notifications(user.uid)
                  : Stream.value([]),
              builder: (context, snapshot) {
                final unreadCount =
                    snapshot.data?.where((n) => !n.read).length ?? 0;

                return Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.surfaceContainer,
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: IconButton(
                          tooltip: 'Notifications',
                          icon: Icon(
                            Icons.notifications_outlined,
                            color: colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                          onPressed: () {
                            vibrationService.lightImpact();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => NotificationCenterPage(
                                  service: NotificationService(
                                    firestore: firestore,
                                  ),
                                  auth: auth,
                                  vibrationService: vibrationService,
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
                                width: 2,
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
          if (showProfileIcon) ...[
            const SizedBox(width: 12),
            Semantics(
              button: true,
              label: 'Open menu',
              child: Tooltip(
                message: 'Open menu',
                child: Material(
                  color: colorScheme.primaryContainer,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: user?.photoURL != null
                      ? Ink.image(
                          image: CachedNetworkImageProvider(user!.photoURL!),
                          fit: BoxFit.cover,
                          width: 40,
                          height: 40,
                          child: Theme(
                            data: Theme.of(
                              context,
                            ).copyWith(splashFactory: NoSplash.splashFactory),
                            child: InkWell(
                              onTap: () {
                                vibrationService.lightImpact();
                                NavigationMenuScope.maybeOf(
                                  context,
                                )?.showMenu(context);
                              },
                            ),
                          ),
                        )
                      : Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(splashFactory: NoSplash.splashFactory),
                          child: InkWell(
                            onTap: () {
                              vibrationService.lightImpact();
                              NavigationMenuScope.maybeOf(
                                context,
                              )?.showMenu(context);
                            },
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Center(
                                child: Text(
                                  initial,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
