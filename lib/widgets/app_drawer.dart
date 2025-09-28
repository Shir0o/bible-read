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
        title: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Compact header without a blue background
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'Bible Read',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            _buildNavItem(
              context,
              index: 0,
              icon: Icons.home_outlined,
              label: 'Home',
            ),
            _buildNavItem(
              context,
              index: 1,
              icon: Icons.rss_feed,
              label: 'Feed',
            ),
            _buildNavItem(
              context,
              index: 3,
              icon: Icons.leaderboard,
              label: 'Leaderboard',
            ),
            _buildNavItem(
              context,
              index: 4,
              icon: Icons.people,
              label: 'Friends',
            ),
            _buildNavItem(
              context,
              index: 5,
              icon: Icons.group,
              label: 'Groups',
            ),
            _buildNavItem(
              context,
              index: 2,
              icon: Icons.flag,
              label: 'Seasonal Challenges',
            ),
            _buildNavItem(
              context,
              index: 6,
              icon: Icons.emoji_events,
              label: 'Achievements',
            ),
            _buildNavItem(
              context,
              index: 7,
              icon: Icons.calendar_today,
              label: 'History',
            ),
            const Divider(),
            _buildNavItem(
              context,
              index: 9,
              icon: Icons.person,
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
