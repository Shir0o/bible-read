import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/notification_preferences.dart';
import '../services/error_logger.dart';
import '../services/notification_preferences_service.dart';
import '../widgets/common_styles.dart';

/// Page to configure notification preferences.
class NotificationSettingsPage extends StatefulWidget {
  /// Service used to load and update preferences.
  final NotificationPreferencesService service;

  /// Auth instance to identify the user.
  final FirebaseAuth auth;

  /// Creates a [NotificationSettingsPage].
  NotificationSettingsPage({
    super.key,
    NotificationPreferencesService? service,
    FirebaseAuth? auth,
  })  : service = service ?? NotificationPreferencesService(),
        auth = auth ?? FirebaseAuth.instance;

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  NotificationPreferences? _prefs;
  bool _loading = true;
  bool _vibrationEnabled = true;

  @override
  void initState() {
    super.initState();
    final user = widget.auth.currentUser;
    if (user != null) {
      Future.wait([
        widget.service.fetchPreferences(user.uid),
        widget.service.fetchVibrationEnabled(user.uid),
      ]).then((result) {
        if (mounted) {
          setState(() {
            _prefs = result[0] as NotificationPreferences;
            _vibrationEnabled = result[1] as bool;
            _loading = false;
          });
        }
      });
    } else {
      _loading = false;
    }
  }

  void _toggle(NotificationType type, bool value) {
    final user = widget.auth.currentUser;
    if (user == null) return;
    final previous = _prefs?[type] ?? false;
    setState(() {
      _prefs = NotificationPreferences(values: {
        ...?_prefs?.values,
        type: value,
      });
    });
    widget.service.updatePreference(user.uid, type, value).catchError((e, st) {
      ErrorLogger.log(e, st);
      if (!mounted) return;
      setState(() {
        _prefs = NotificationPreferences(values: {
          ...?_prefs?.values,
          type: previous,
        });
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update preferences')),
      );
    });
  }

  void _toggleVibration(bool value) {
    final user = widget.auth.currentUser;
    if (user == null) return;
    final previous = _vibrationEnabled;
    setState(() {
      _vibrationEnabled = value;
    });
    widget.service.updateVibrationEnabled(user.uid, value).catchError((e, st) {
      ErrorLogger.log(e, st);
      if (!mounted) return;
      setState(() {
        _vibrationEnabled = previous;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update preferences')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar('Notification Settings'),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_prefs == null
                ? const Center(child: Text('Please sign in'))
                : ListView(
                    children: [
                      ...NotificationType.values.map(
                        (type) => SwitchListTile(
                          title: Text(_label(type)),
                          value: _prefs![type],
                          onChanged: (val) => _toggle(type, val),
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('Vibration'),
                        value: _vibrationEnabled,
                        onChanged: _toggleVibration,
                      ),
                    ],
                  )),
      ),
    );
  }

  String _label(NotificationType type) {
    switch (type) {
      case NotificationType.like:
        return 'Like Notifications';
      case NotificationType.nudge:
        return 'Nudge Notifications';
      case NotificationType.signup:
        return 'Signup Alerts';
      case NotificationType.achievement:
        return 'Achievement Notifications';
      case NotificationType.friendRequest:
        return 'Friend Request Notifications';
      case NotificationType.comment:
        return 'Comment Notifications';
      case NotificationType.groupJoinRequest:
        return 'Group Join Request Notifications';
      case NotificationType.groupScheduleUpdate:
        return 'Group Schedule Update Notifications';
    }
  }
}
