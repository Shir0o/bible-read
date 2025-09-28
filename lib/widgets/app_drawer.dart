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
            CommonStyles.buildTappableCard(
              onTap: () {
                unawaited(vibrationService.lightImpact());
                Navigator.pop(context);
                onNavigate(3);
              },
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: const ListTile(
                dense: true,
                visualDensity: VisualDensity(vertical: -3),
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.leaderboard),
                title: Text('Leaderboard'),
              ),
            ),
            CommonStyles.buildTappableCard(
              onTap: () {
                unawaited(vibrationService.lightImpact());
                Navigator.pop(context);
                onNavigate(4);
              },
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: const ListTile(
                dense: true,
                visualDensity: VisualDensity(vertical: -3),
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.people),
                title: Text('Friends'),
              ),
            ),
            CommonStyles.buildTappableCard(
              onTap: () {
                unawaited(vibrationService.lightImpact());
                Navigator.pop(context);
                onNavigate(5);
              },
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: const ListTile(
                dense: true,
                visualDensity: VisualDensity(vertical: -3),
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.group),
                title: Text('Groups'),
              ),
            ),
            CommonStyles.buildTappableCard(
              onTap: () {
                unawaited(vibrationService.lightImpact());
                Navigator.pop(context);
                onNavigate(2);
              },
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: const ListTile(
                dense: true,
                visualDensity: VisualDensity(vertical: -3),
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.flag),
                title: Text('Seasonal Challenges'),
              ),
            ),
            CommonStyles.buildTappableCard(
              onTap: () {
                unawaited(vibrationService.lightImpact());
                Navigator.pop(context);
                onNavigate(6);
              },
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: const ListTile(
                dense: true,
                visualDensity: VisualDensity(vertical: -3),
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.emoji_events),
                title: Text('Achievements'),
              ),
            ),
            CommonStyles.buildTappableCard(
              onTap: () {
                unawaited(vibrationService.lightImpact());
                Navigator.pop(context);
                onNavigate(7);
              },
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: const ListTile(
                dense: true,
                visualDensity: VisualDensity(vertical: -3),
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.calendar_today),
                title: Text('History'),
              ),
            ),
            const Divider(),
            CommonStyles.buildTappableCard(
              onTap: () {
                unawaited(vibrationService.lightImpact());
                Navigator.pop(context);
                onNavigate(9);
              },
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: const ListTile(
                dense: true,
                visualDensity: VisualDensity(vertical: -3),
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.person),
                title: Text('Profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
