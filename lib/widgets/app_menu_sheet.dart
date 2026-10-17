import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../pages/admin/feedback_admin_page.dart';
import '../pages/notification_center_page.dart';
import '../pages/settings_page.dart';
import '../services/admin_role_service.dart';
import '../services/feedback_service.dart';
import '../services/google_sign_in_factory.dart';
import '../services/notification_service.dart';
import '../services/reading_status_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import 'animated_page_route.dart';
import 'app_bottom_sheet.dart';
import 'common_styles.dart';

/// The sheet opened from the avatar: a profile row, up to three of the newest
/// unread notifications (with "See all"), then Settings and, for admins, Inbox.
/// Sign out lives in Settings.
class AppMenuSheet extends StatefulWidget {
  const AppMenuSheet({
    super.key,
    required this.vibrationService,
    required this.parentContext,
    this.feedbackService,
    this.adminRoleService,
    this.auth,
    this.firestore,
  });

  final VibrationService vibrationService;
  final BuildContext parentContext;
  final FeedbackService? feedbackService;
  final AdminRoleService? adminRoleService;
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;

  static Future<void> show({
    required BuildContext context,
    VibrationService? vibrationService,
    FeedbackService? feedbackService,
    AdminRoleService? adminRoleService,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) {
    if (!context.mounted) {
      return Future.value();
    }

    return showAppSheet<void>(
      context: context,
      builder: (sheetContext) {
        return AppMenuSheet(
          vibrationService: vibrationService ?? const VibrationService(),
          parentContext: context,
          feedbackService: feedbackService,
          adminRoleService: adminRoleService,
          auth: auth,
          firestore: firestore,
        );
      },
    );
  }

  @override
  State<AppMenuSheet> createState() => _AppMenuSheetState();
}

class _AppMenuSheetState extends State<AppMenuSheet> {
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminRole();
  }

  Future<void> _checkAdminRole() async {
    final service = widget.adminRoleService;
    if (service == null) return;

    if (service.cachedAdminRole != null) {
      setState(() {
        _isAdmin = service.cachedAdminRole!;
      });
    }

    try {
      final isAdmin = await service.isAdmin(allowStale: true);
      if (mounted && isAdmin != _isAdmin) {
        setState(() {
          _isAdmin = isAdmin;
        });
      }
    } catch (_) {
      // Ignore errors
    }
  }

  /// Closes the sheet, then runs [action] against the page that opened it.
  void _closeThen(void Function(BuildContext context) action) {
    unawaited(widget.vibrationService.lightImpact());
    Navigator.of(context).pop();
    action(widget.parentContext);
  }

  void _openNotificationCenter(BuildContext context) {
    final auth = widget.auth ?? FirebaseAuth.instance;
    final firestore = widget.firestore ?? FirebaseFirestore.instance;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotificationCenterPage(
          service: NotificationService(firestore: firestore),
          auth: auth,
          vibrationService: widget.vibrationService,
        ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          auth: widget.auth ?? FirebaseAuth.instance,
          firestore: widget.firestore ?? FirebaseFirestore.instance,
          googleSignInProvider: createGoogleSignIn,
          vibrationService: widget.vibrationService,
        ),
      ),
    );
  }

  void _openInbox(BuildContext context) {
    Navigator.of(context).push(
      animatedPageRoute(
        FeedbackAdminPage(
          firestore: widget.feedbackService?.firestore,
          auth: widget.feedbackService?.auth,
          adminRoleService: widget.adminRoleService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final auth = widget.auth;
    final firestore = widget.firestore;
    final uid = auth?.currentUser?.uid;
    final hasNotifications = auth != null && firestore != null && uid != null;

    return SingleChildScrollView(
      key: const Key('menu_scroll_view'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gap20,
        AppSpacing.gap16,
        AppSpacing.gap20,
        AppSpacing.gap32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileRow(auth: auth, firestore: firestore),
          if (hasNotifications)
            StreamBuilder<List<AppNotification>>(
              stream:
                  NotificationService(firestore: firestore).notifications(uid),
              builder: (context, snapshot) {
                final unread = (snapshot.data ?? const <AppNotification>[])
                    .where((n) => !n.read)
                    .toList();
                return _NotificationsSection(
                  unread: unread,
                  onSeeAll: () => _closeThen(_openNotificationCenter),
                  onOpen: (n) => _closeThen(
                    (ctx) => unawaited(
                      openNotification(
                        ctx,
                        notification: n,
                        service: NotificationService(firestore: firestore),
                        auth: auth,
                        vibrationService: widget.vibrationService,
                      ),
                    ),
                  ),
                );
              },
            ),
          Divider(height: AppSpacing.gap24, color: colorScheme.outlineVariant),
          _SheetRow(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () => _closeThen(_openSettings),
          ),
          if (_isAdmin)
            _SheetRow(
              icon: Icons.inbox_outlined,
              label: 'Inbox',
              tag: 'Admin',
              onTap: () => _closeThen(_openInbox),
            ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({this.auth, this.firestore});

  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final user = auth?.currentUser;
    final rawName = (user?.displayName ?? '').trim();
    final name = rawName.isEmpty ? 'Reader' : rawName;
    final photoUrl = user?.photoURL;

    Widget subtitle(String text) =>
        Text(text, style: theme.textTheme.bodySmall);

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primaryContainer,
            image: photoUrl != null
                ? DecorationImage(
                    image: CachedNetworkImageProvider(photoUrl),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          alignment: Alignment.center,
          child: photoUrl == null
              ? Text(
                  name[0].toUpperCase(),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: colorScheme.primary),
                )
              : null,
        ),
        const SizedBox(width: AppSpacing.gap12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 1),
              if (user != null && firestore != null)
                StreamBuilder<int>(
                  stream: ReadingStatusService(firestore: firestore!)
                      .watchStreak(user.uid),
                  builder: (context, snapshot) {
                    final streak = snapshot.data ?? 0;
                    return subtitle(
                      streak > 0 ? '$streak-day streak' : 'Keep showing up.',
                    );
                  },
                )
              else
                subtitle('Keep showing up.'),
            ],
          ),
        ),
      ],
    );
  }
}

class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection({
    required this.unread,
    required this.onSeeAll,
    required this.onOpen,
  });

  final List<AppNotification> unread;
  final VoidCallback onSeeAll;
  final ValueChanged<AppNotification> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.gap16),
        Row(
          children: [
            Expanded(
              child: Text(
                unread.isEmpty
                    ? 'NOTIFICATIONS'
                    : 'NOTIFICATIONS · ${unread.length} NEW',
                style: AppTextStyles.caption(context)
                    .copyWith(color: colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: onSeeAll,
              child: const Text('See all'),
            ),
          ],
        ),
        for (final n in unread.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.gap8),
            child: Material(
              color: appColors.primarySoft,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.rInset),
                side: BorderSide(color: appColors.primaryLine),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onOpen(n),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.gap12,
                    vertical: AppSpacing.gap12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.message ?? defaultNotificationMessage(n),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.gap8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colorScheme.tertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tag,
  });

  final IconData icon;
  final String label;
  final String? tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.rInset),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.gap12,
          horizontal: AppSpacing.gap4,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.gap12),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (tag != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.gap8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.gap12),
                ),
                child: Text(
                  tag!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
