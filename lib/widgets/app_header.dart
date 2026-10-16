import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../services/notification_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import 'common_styles.dart';
import 'navigation_menu_scope.dart';

/// An optional pill on the right of [AppHeader], e.g. Circle's "Invite".
class AppHeaderAction {
  const AppHeaderAction({
    required this.label,
    required this.onPressed,
    this.icon = Icons.add,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

/// The shared tab header (design C): a small dim eyebrow over a large serif
/// title on the left; on the right an optional [action] pill, then the avatar
/// that opens the menu sheet. The avatar carries the unread-notification count.
class AppHeader extends StatelessWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final VibrationService vibrationService;
  final DateTime Function() dateProvider;
  final String eyebrow;
  final String title;
  final AppHeaderAction? action;

  /// Optional status indicator shown before the avatar (Today's sun mark).
  final Widget? status;

  const AppHeader({
    super.key,
    required this.auth,
    required this.firestore,
    required this.vibrationService,
    required this.dateProvider,
    required this.eyebrow,
    required this.title,
    this.action,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 80),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.hPadding,
        AppSpacing.gap8,
        AppSpacing.hPadding,
        AppSpacing.gap16,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  style: AppTextStyles.caption(context).copyWith(
                    color: colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.topBarTitle(context).copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.gap12),
            _ActionPill(action: action!, vibrationService: vibrationService),
          ],
          if (status != null) ...[
            const SizedBox(width: AppSpacing.gap12),
            status!,
          ],
          const SizedBox(width: AppSpacing.gap12),
          StreamBuilder<List<AppNotification>>(
            stream: user != null
                ? NotificationService(firestore: firestore)
                    .notifications(user.uid)
                : Stream.value(const <AppNotification>[]),
            builder: (context, snapshot) {
              final unread = snapshot.data?.where((n) => !n.read).length ?? 0;
              return _Avatar(
                user: user,
                unread: unread,
                vibrationService: vibrationService,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.action, required this.vibrationService});

  final AppHeaderAction action;
  final VibrationService vibrationService;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);
    return Material(
      color: appColors.primarySoft,
      shape: StadiumBorder(side: BorderSide(color: appColors.primaryLine)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          vibrationService.lightImpact();
          action.onPressed();
        },
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gap12),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                action.icon,
                size: AppSpacing.iconMd,
                color: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: AppSpacing.gap4),
              Text(
                action.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.user,
    required this.unread,
    required this.vibrationService,
  });

  final User? user;
  final int unread;
  final VibrationService vibrationService;

  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = (user?.displayName ?? '').trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final photoUrl = user?.photoURL;
    final label =
        unread > 0 ? 'Open menu, $unread unread notifications' : 'Open menu';

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: 'Open menu',
        child: SizedBox(
          width: _size,
          height: _size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Material(
                  color: colorScheme.primaryContainer,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      vibrationService.lightImpact();
                      NavigationMenuScope.maybeOf(context)?.showMenu(context);
                    },
                    child: photoUrl != null
                        ? Ink.image(
                            image: CachedNetworkImageProvider(photoUrl),
                            fit: BoxFit.cover,
                          )
                        : Center(
                            child: Text(
                              initial,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: colorScheme.primary),
                            ),
                          ),
                  ),
                ),
              ),
              if (unread > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: IgnorePointer(
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 18, minHeight: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colorScheme.tertiary,
                        borderRadius: BorderRadius.circular(AppSpacing.rInset),
                        border: Border.all(
                          color: colorScheme.surface,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        unread > 9 ? '9+' : '$unread',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colorScheme.onTertiary,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
