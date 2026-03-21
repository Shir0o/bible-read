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

class AppHeader extends StatelessWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final VibrationService vibrationService;
  final DateTime Function() dateProvider;
  final String? customGreeting;
  final bool showProfileIcon;
  final bool showNotificationBell;
  final bool showGreeting;

  const AppHeader({
    super.key,
    required this.auth,
    required this.firestore,
    required this.vibrationService,
    required this.dateProvider,
    this.customGreeting,
    this.showProfileIcon = true,
    this.showNotificationBell = true,
    this.showGreeting = true,
  });

  String _getGreeting() {
    if (customGreeting != null) return customGreeting!;

    final hour = dateProvider().hour;
    if (hour < 12) {
      return 'Good Morning,';
    } else if (hour < 17) {
      return 'Good Afternoon,';
    } else {
      return 'Good Evening,';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    final colorScheme = Theme.of(context).colorScheme;
    final firstName = (user?.displayName ?? 'Friend').split(' ').first;

    return Container(
      constraints: const BoxConstraints(minHeight: 80),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Row(
        children: [
          // Avatar
          if (showProfileIcon) ...[
            Semantics(
              button: true,
              label: 'Open menu',
              child: Tooltip(
                message: 'Open menu',
                child: Material(
                  color: colorScheme.surfaceContainerHighest,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: user?.photoURL != null
                      ? Ink.image(
                          image: CachedNetworkImageProvider(user!.photoURL!),
                          fit: BoxFit.cover,
                          width: 40,
                          height: 40,
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              splashFactory: NoSplash.splashFactory,
                            ),
                            child: InkWell(
                              onTap: () {
                                vibrationService.lightImpact();
                                NavigationMenuScope.maybeOf(context)
                                    ?.showMenu(context);
                              },
                            ),
                          ),
                        )
                      : Theme(
                          data: Theme.of(context).copyWith(
                            splashFactory: NoSplash.splashFactory,
                          ),
                          child: InkWell(
                            onTap: () {
                              vibrationService.lightImpact();
                              NavigationMenuScope.maybeOf(context)
                                  ?.showMenu(context);
                            },
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Icon(Icons.person,
                                  color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Greeting & Name
          Expanded(
            child: showGreeting
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _getGreeting(),
                        style: AppTextStyles.body(context).copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        firstName,
                        style: AppTextStyles.title(context).copyWith(
                          color: colorScheme.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          // Notification Button
          if (showNotificationBell) ...[
            const SizedBox(width: 12),
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
                    shape: BoxShape.circle,
                    color: colorScheme.surfaceContainer,
                    border: Border.all(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.1)),
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
                                  service:
                                      NotificationService(firestore: firestore),
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
                                  width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
