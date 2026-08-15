import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../pages/admin/feedback_admin_page.dart';
import '../pages/feedback_page.dart';
import '../models/app_notification.dart';
import '../services/admin_role_service.dart';
import '../services/feedback_service.dart';
import '../services/vibration_service.dart';
import '../services/friend_service.dart';
import 'animated_page_route.dart';
import '../pages/notification_center_page.dart';
import '../services/notification_service.dart';

import '../pages/settings_page.dart';
import '../pages/bible_progress_page.dart';
import '../pages/groups_page.dart';
import '../services/google_sign_in_factory.dart';
import '../services/group_service.dart';

/// The hub sheet opened from the avatar — matches the design's `MenuSheet`:
/// a profile header, a two-column grid of destinations, and a quiet full-width
/// Sign Out row at the bottom.
class AppMenuSheet extends StatefulWidget {
  const AppMenuSheet({
    super.key,
    required this.onNavigate,
    required this.vibrationService,
    required this.parentContext,
    this.feedbackService,
    this.adminRoleService,
    this.auth,
    this.firestore,
  });

  final ValueChanged<int> onNavigate;
  final VibrationService vibrationService;
  final BuildContext parentContext;
  final FeedbackService? feedbackService;
  final AdminRoleService? adminRoleService;
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;

  static Future<void> show({
    required BuildContext context,
    required ValueChanged<int> onNavigate,
    VibrationService? vibrationService,
    FeedbackService? feedbackService,
    AdminRoleService? adminRoleService,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) {
    if (!context.mounted) {
      return Future.value();
    }

    return showModalBottomSheet(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return AppMenuSheet(
          onNavigate: onNavigate,
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

  List<_MenuItem> _menuItems() {
    try {
      final auth = widget.auth ?? FirebaseAuth.instance;
      final firestore = widget.firestore ?? FirebaseFirestore.instance;
      return _buildFullMenuList(auth, firestore);
    } catch (_) {
      return _buildFallbackMenuList();
    }
  }

  List<_MenuItem> _buildFullMenuList(
    FirebaseAuth auth,
    FirebaseFirestore firestore,
  ) {
    final items = [
      _MenuItem(
        icon: Icons.settings_outlined,
        label: 'Settings',
        onTap: (context) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SettingsPage(
                auth: auth,
                firestore: firestore,
                googleSignInProvider: createGoogleSignIn,
                friendService: FriendService(firestore: firestore),
                vibrationService: widget.vibrationService,
              ),
            ),
          );
        },
      ),
      _MenuItem(
        icon: Icons.notifications_outlined,
        label: 'Notifications',
        badge: true,
        onTap: (context) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NotificationCenterPage(
                service: NotificationService(firestore: firestore),
                auth: auth,
                vibrationService: widget.vibrationService,
              ),
            ),
          );
        },
      ),
      _MenuItem(icon: Icons.people_outline, label: 'Friends', index: 4),
      _MenuItem(
        icon: Icons.emoji_events_outlined,
        label: 'Challenges',
        index: 5,
      ),
      _MenuItem(
        icon: Icons.explore_outlined,
        label: 'Groups',
        onTap: (context) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GroupsPage(
                groupService: GroupService(firestore: firestore),
                auth: auth,
                vibrationService: widget.vibrationService,
              ),
            ),
          );
        },
      ),
      _MenuItem(
        icon: Icons.menu_book_outlined,
        label: 'Library',
        onTap: (context) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BibleProgressPage(
                auth: auth,
                firestore: firestore,
                vibrationService: widget.vibrationService,
              ),
            ),
          );
        },
      ),
      _MenuItem(
        icon: Icons.bug_report_outlined,
        label: 'Feedback',
        onTap: (context) {
          final feedback = widget.feedbackService ?? FeedbackService();
          Navigator.of(context).push(
            animatedPageRoute(
              FeedbackPage(
                initialTab: FeedbackTab.feature,
                feedbackService: feedback,
                vibrationService: widget.vibrationService,
                parentMessenger: ScaffoldMessenger.of(context),
              ),
            ),
          );
        },
      ),
    ];

    if (_isAdmin) {
      items.add(
        _MenuItem(
          icon: Icons.inbox_outlined,
          label: 'Inbox',
          onTap: (context) {
            Navigator.of(context).push(
              animatedPageRoute(
                FeedbackAdminPage(
                  firestore: widget.feedbackService?.firestore,
                  auth: widget.feedbackService?.auth,
                  adminRoleService: widget.adminRoleService,
                ),
              ),
            );
          },
        ),
      );
    }
    return items;
  }

  List<_MenuItem> _buildFallbackMenuList() {
    return [
      _MenuItem(icon: Icons.people_outline, label: 'Friends', index: 4),
      _MenuItem(
        icon: Icons.bug_report_outlined,
        label: 'Feedback',
        onTap: (context) {
          final feedback = widget.feedbackService ?? FeedbackService();
          Navigator.of(context).push(
            animatedPageRoute(
              FeedbackPage(
                initialTab: FeedbackTab.feature,
                feedbackService: feedback,
                vibrationService: widget.vibrationService,
                parentMessenger: ScaffoldMessenger.of(context),
              ),
            ),
          );
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return _MenuContents(
      items: _menuItems(),
      vibrationService: widget.vibrationService,
      onNavigate: widget.onNavigate,
      parentContext: widget.parentContext,
      auth: widget.auth,
      firestore: widget.firestore,
    );
  }
}

class _MenuContents extends StatelessWidget {
  const _MenuContents({
    required this.items,
    required this.vibrationService,
    required this.onNavigate,
    required this.parentContext,
    this.auth,
    this.firestore,
  });

  final List<_MenuItem> items;
  final VibrationService vibrationService;
  final ValueChanged<int> onNavigate;
  final BuildContext parentContext;
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final textStyle =
        theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600) ??
            const TextStyle(fontWeight: FontWeight.w600);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            blurRadius: 20,
            color: colorScheme.shadow.withValues(alpha: 0.16),
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          key: const Key('menu_scroll_view'),
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(height: 16),
              _ProfileHeader(auth: auth),
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final double availableWidth = MediaQuery.of(
                    context,
                  ).size.width;
                  final bool compact = availableWidth < 360;
                  final double horizontalPadding = 40.0; // 20 on each side
                  final double contentWidth =
                      availableWidth - horizontalPadding;

                  final double baseWidth =
                      compact ? contentWidth : (contentWidth - 9) / 2;
                  final double buttonWidth = compact
                      ? baseWidth
                      : baseWidth.clamp(140.0, 240.0).toDouble();

                  return Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    alignment: compact
                        ? WrapAlignment.center
                        : WrapAlignment.spaceBetween,
                    children: items
                        .map(
                          (item) => SizedBox(
                            width: buttonWidth, // Ensure equal width
                            child: _MenuActionButton(
                              item: item,
                              onNavigate: onNavigate,
                              vibrationService: vibrationService,
                              textStyle: textStyle,
                              parentContext: parentContext,
                              auth: auth,
                              firestore: firestore,
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 9),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    alignment: Alignment.center,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    backgroundColor: colorScheme.secondaryContainer,
                    foregroundColor: colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () {
                    unawaited(vibrationService.lightImpact());
                    Navigator.of(context).pop();
                    onNavigate(10);
                  },
                  icon: const Icon(Icons.logout, size: 19),
                  label: Text(
                    'Sign Out',
                    style: textStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({this.auth});

  final FirebaseAuth? auth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = auth?.currentUser;
    final name = user?.displayName ?? 'Friend';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primaryContainer,
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: user?.photoURL != null
                ? Image.network(
                    user!.photoURL!,
                    fit: BoxFit.cover,
                    width: 44,
                    height: 44,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Text(
                        initial,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  )
                : Text(
                    initial,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Keep showing up.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuActionButton extends StatelessWidget {
  const _MenuActionButton({
    required this.item,
    required this.onNavigate,
    required this.vibrationService,
    required this.textStyle,
    required this.parentContext,
    this.auth,
    this.firestore,
  });

  final _MenuItem item;
  final ValueChanged<int> onNavigate;
  final VibrationService vibrationService;
  final TextStyle textStyle;
  final BuildContext parentContext;
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    Widget badge = const SizedBox.shrink();
    if (item.badge && auth != null && firestore != null) {
      badge = StreamBuilder<List<AppNotification>>(
        stream: NotificationService(firestore: firestore!)
            .notifications(auth!.currentUser?.uid ?? ''),
        builder: (context, snapshot) {
          final unread = snapshot.data?.where((n) => !n.read).length ?? 0;
          if (unread == 0) return const SizedBox.shrink();
          return Positioned(
            top: 11,
            right: 11,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: colorScheme.tertiary,
                shape: BoxShape.circle,
              ),
            ),
          );
        },
      );
    }

    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: colorScheme.secondaryContainer,
        foregroundColor: colorScheme.primary,
      ),
      onPressed: () {
        unawaited(vibrationService.lightImpact());
        Navigator.of(context).pop();
        if (item.onTap != null) {
          item.onTap!(parentContext);
        } else if (item.index != null) {
          onNavigate(item.index!);
        }
      },
      icon: SizedBox(
        width: 28,
        child: Stack(
          children: [
            Icon(item.icon, size: 20),
            badge,
          ],
        ),
      ),
      label: Text(
        item.label,
        style: textStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem({
    this.index,
    required this.icon,
    required this.label,
    this.onTap,
    this.badge = false,
  }) : assert(
          index != null || onTap != null,
          'Either index or onTap must be provided.',
        );

  final int? index;
  final IconData icon;
  final String label;
  final bool badge;
  final void Function(BuildContext context)? onTap;
}
