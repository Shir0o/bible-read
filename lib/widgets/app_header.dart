import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

  /// Optional ambient sync status indicator shown beside the date eyebrow.
  final Widget? syncIndicator;

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
    this.syncIndicator,
  });

  static const double _maxTitleScale = 1.15;

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
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.gap8,
                  children: [
                    Text(
                      eyebrow.toUpperCase(),
                      style: AppTextStyles.caption(context).copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (syncIndicator != null) syncIndicator!,
                  ],
                ),
                const SizedBox(height: AppSpacing.gap4),
                // The title is already display-sized; past 1.15x it would
                // squeeze to an ellipsis beside the action pill.
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: _maxTitleScale,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.topBarTitle(context).copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.gap12),
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: _maxTitleScale,
              child: _ActionPill(
                  action: action!, vibrationService: vibrationService),
            ),
          ],
          if (status != null) ...[
            const SizedBox(width: AppSpacing.gap12),
            status!,
          ],
          const SizedBox(width: AppSpacing.gap12),
          _Avatar(
            user: user,
            vibrationService: vibrationService,
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
          constraints: const BoxConstraints(minHeight: 48),
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
    required this.vibrationService,
  });

  final User? user;
  final VibrationService vibrationService;

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = (user?.displayName ?? '').trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final photoUrl = user?.photoURL;

    // The outer node owns the label, so TalkBack and VoiceOver announce one
    // clean "Open menu" button. The InkWell inside keeps its tap action and
    // focus flags, which merge into this node.
    return Semantics(
      container: true,
      button: true,
      label: 'Open menu',
      child: Tooltip(
        message: 'Open menu',
        excludeFromSemantics: true,
        child: SizedBox(
          width: _size,
          height: _size,
          child: Material(
            color: colorScheme.primaryContainer,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                vibrationService.lightImpact();
                NavigationMenuScope.maybeOf(context)?.showMenu(context);
              },
              child: ExcludeSemantics(
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
        ),
      ),
    );
  }
}
