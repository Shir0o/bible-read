import 'dart:async';

import 'package:flutter/material.dart';

import '../services/vibration_service.dart';
import 'common_styles.dart';

class AppDrawer extends StatelessWidget {
  final ValueChanged<int> onNavigate;

  final VibrationService vibrationService;

  const AppDrawer({
    super.key,
    required this.onNavigate,
    VibrationService? vibrationService,
  }) : vibrationService = vibrationService ?? const VibrationService();

  Widget _buildNavItem(
    BuildContext context, {
    required int index,
    required IconData icon,
    required String label,
    required TextStyle textStyle,
  }) {
    return CommonStyles.buildTappableCard(
      onTap: () {
        unawaited(vibrationService.lightImpact());
        Navigator.pop(context);
        onNavigate(index);
      },
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -3),
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(label, style: textStyle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navigationTextStyle = theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: (theme.textTheme.bodyLarge?.fontSize ?? 16) - 1,
        ) ??
        const TextStyle(fontSize: 15, fontWeight: FontWeight.w600);

    final drawerTitleStyle = theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ) ??
        const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        );

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Compact header without a blue background
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('Bible Read', style: drawerTitleStyle),
            ),
            _buildNavItem(
              context,
              index: 0,
              icon: Icons.home_outlined,
              label: 'Home',
              textStyle: navigationTextStyle,
            ),
            _buildNavItem(
              context,
              index: 1,
              icon: Icons.rss_feed,
              label: 'Feed',
              textStyle: navigationTextStyle,
            ),
            _buildNavItem(
              context,
              index: 3,
              icon: Icons.leaderboard,
              label: 'Leaderboard',
              textStyle: navigationTextStyle,
            ),
            _buildNavItem(
              context,
              index: 4,
              icon: Icons.people,
              label: 'Friends',
              textStyle: navigationTextStyle,
            ),
            _buildNavItem(
              context,
              index: 5,
              icon: Icons.group,
              label: 'Groups',
              textStyle: navigationTextStyle,
            ),
            _buildNavItem(
              context,
              index: 2,
              icon: Icons.flag,
              label: 'Seasonal Challenges',
              textStyle: navigationTextStyle,
            ),
            _buildNavItem(
              context,
              index: 6,
              icon: Icons.emoji_events,
              label: 'Achievements',
              textStyle: navigationTextStyle,
            ),
            _buildNavItem(
              context,
              index: 7,
              icon: Icons.calendar_today,
              label: 'History',
              textStyle: navigationTextStyle,
            ),
            const Divider(),
            _buildNavItem(
              context,
              index: 9,
              icon: Icons.person,
              label: 'Profile',
              textStyle: navigationTextStyle,
            ),
          ],
        ),
      ),
    );
  }
}
