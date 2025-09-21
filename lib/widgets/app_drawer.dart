import 'dart:async';

import 'package:flutter/material.dart';

import '../services/vibration_service.dart';

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
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF0D47A1)),
              child: Text(
                'Bible Read',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.leaderboard),
              title: const Text('Leaderboard'),
              onTap: () {
                unawaited(vibrationService.lightImpact());
                Navigator.pop(context);
                onNavigate(3);
              },
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Friends'),
              onTap: () {
                unawaited(vibrationService.lightImpact());
                Navigator.pop(context);
                onNavigate(4);
              },
            ),
            ListTile(
              leading: const Icon(Icons.group),
              title: const Text('Groups'),
              onTap: () {
                unawaited(vibrationService.lightImpact());
                Navigator.pop(context);
                onNavigate(5);
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag),
              title: const Text('Seasonal Challenges'),
              onTap: () {
                unawaited(vibrationService.lightImpact());
                Navigator.pop(context);
                onNavigate(2);
              },
            ),
            ListTile(
              leading: const Icon(Icons.emoji_events),
              title: const Text('Achievements'),
              onTap: () {
                unawaited(vibrationService.lightImpact());
                Navigator.pop(context);
                onNavigate(6);
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('History'),
              onTap: () {
                unawaited(vibrationService.lightImpact());
                Navigator.pop(context);
                onNavigate(7);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Profile'),
              onTap: () {
                unawaited(vibrationService.lightImpact());
                Navigator.pop(context);
                onNavigate(9);
              },
            ),
          ],
        ),
      ),
    );
  }
}
