import 'dart:async';

import 'package:flutter/material.dart';

import '../pages/admin/feedback_admin_page.dart';
import '../pages/feedback_page.dart';
import '../services/admin_role_service.dart';
import '../services/feedback_service.dart';
import '../services/vibration_service.dart';
import 'animated_page_route.dart';

class AppMenuSheet extends StatelessWidget {
  const AppMenuSheet({
    super.key,
    required this.onNavigate,
    required this.vibrationService,
    required this.parentContext,
    this.isAdmin = false,
    this.feedbackService,
    this.adminRoleService,
  });

  final ValueChanged<int> onNavigate;
  final VibrationService vibrationService;
  final BuildContext parentContext;
  final bool isAdmin;
  final FeedbackService? feedbackService;
  final AdminRoleService? adminRoleService;

  static Future<void> show({
    required BuildContext context,
    required ValueChanged<int> onNavigate,
    VibrationService? vibrationService,
    FeedbackService? feedbackService,
    AdminRoleService? adminRoleService,
  }) async {
    final service = vibrationService ?? const VibrationService();
    final bool cachedAdmin = adminRoleService?.cachedAdminRole ?? false;
    final Future<bool>? adminRoleFuture =
        adminRoleService?.isAdmin(allowStale: true);

    if (!context.mounted) {
      return;
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FutureBuilder<bool>(
          future: adminRoleFuture,
          initialData: cachedAdmin,
          builder: (context, snapshot) {
            final bool resolvedIsAdmin = snapshot.data ?? cachedAdmin;
            return AppMenuSheet(
              onNavigate: onNavigate,
              vibrationService: service,
              parentContext: context,
              isAdmin: resolvedIsAdmin,
              feedbackService: feedbackService,
              adminRoleService: adminRoleService,
            );
          },
        );
      },
    );
  }

  List<_MenuItem> _menuItems(bool isAdmin) {
    final items = [
      const _MenuItem(
          index: 6, icon: Icons.emoji_events, label: 'Achievements'),
      const _MenuItem(
        index: 14,
        icon: Icons.checklist,
        label: 'Book Tracker',
      ),
      const _MenuItem(index: 1, icon: Icons.feed, label: 'Feed'),
      const _MenuItem(index: 4, icon: Icons.people, label: 'Friends'),
      const _MenuItem(index: 5, icon: Icons.group, label: 'Groups'),
      const _MenuItem(index: 7, icon: Icons.calendar_today, label: 'History'),
      const _MenuItem(
        index: 8,
        icon: Icons.local_fire_department,
        label: 'Friendly Streaks',
      ),
      const _MenuItem(index: 0, icon: Icons.home_outlined, label: 'Home'),
      const _MenuItem(index: 3, icon: Icons.leaderboard, label: 'Leaderboard'),
      const _MenuItem(
          index: 11, icon: Icons.notifications, label: 'Notifications'),
      const _MenuItem(index: 10, icon: Icons.person, label: 'Profile'),
      const _MenuItem(
          index: 12, icon: Icons.fitness_center, label: 'Daily Exercise'),
      const _MenuItem(
        index: 13,
        icon: Icons.manage_search,
        label: 'Exercise Challenges',
      ),
      const _MenuItem(index: 2, icon: Icons.flag, label: 'Seasonal Challenges'),
      _MenuItem(
        icon: Icons.feedback,
        label: 'Feedback',
        onTap: (context) {
          final feedback = feedbackService ?? FeedbackService();
          Navigator.of(context).push(
            animatedPageRoute(
              FeedbackPage(
                initialTab: FeedbackTab.feature,
                feedbackService: feedback,
                vibrationService: vibrationService,
                parentMessenger: ScaffoldMessenger.of(context),
              ),
            ),
          );
        },
      ),
    ];

    if (isAdmin) {
      items.add(
        _MenuItem(
          icon: Icons.inventory_2,
          label: 'Feedback Inbox',
          onTap: (context) {
            Navigator.of(context).push(
              animatedPageRoute(
                FeedbackAdminPage(
                  firestore: feedbackService?.firestore,
                  auth: feedbackService?.auth,
                  adminRoleService: adminRoleService,
                ),
              ),
            );
          },
        ),
      );
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return _MenuContents(
      items: _menuItems(isAdmin),
      vibrationService: vibrationService,
      onNavigate: onNavigate,
      parentContext: parentContext,
    );
  }
}

class _MenuContents extends StatelessWidget {
  const _MenuContents({
    required this.items,
    required this.vibrationService,
    required this.onNavigate,
    required this.parentContext,
  });

  final List<_MenuItem> items;
  final VibrationService vibrationService;
  final ValueChanged<int> onNavigate;
  final BuildContext parentContext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ) ??
        const TextStyle(fontWeight: FontWeight.w600);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 20,
            color: Colors.black26,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
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
              Text(
                'Menu',
                style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ) ??
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final double availableWidth = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : MediaQuery.of(context).size.width;
                  final bool compact = availableWidth < 360;
                  final double baseWidth =
                      compact ? availableWidth : (availableWidth - 40) / 2;
                  final double buttonWidth = compact
                      ? baseWidth
                      : baseWidth.clamp(140.0, 240.0).toDouble();

                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: compact
                        ? WrapAlignment.center
                        : WrapAlignment.spaceBetween,
                    children: items
                        .map(
                          (item) => SizedBox(
                            width: buttonWidth,
                            child: _MenuActionButton(
                              item: item,
                              onNavigate: onNavigate,
                              vibrationService: vibrationService,
                              textStyle: textStyle,
                              parentContext: parentContext,
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
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
  });

  final _MenuItem item;
  final ValueChanged<int> onNavigate;
  final VibrationService vibrationService;
  final TextStyle textStyle;
  final BuildContext parentContext;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: colorScheme.secondaryContainer,
        foregroundColor: colorScheme.onSecondaryContainer,
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
      icon: Icon(item.icon),
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
  }) : assert(index != null || onTap != null,
            'Either index or onTap must be provided.');

  final int? index;
  final IconData icon;
  final String label;
  final void Function(BuildContext context)? onTap;
}
