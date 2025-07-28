import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/notification_preferences.dart';
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

  @override
  void initState() {
    super.initState();
    final user = widget.auth.currentUser;
    if (user != null) {
      widget.service.fetchPreferences(user.uid).then((p) {
        if (mounted) {
          setState(() {
            _prefs = p;
            _loading = false;
          });
        }
      });
    } else {
      _loading = false;
    }
  }

  Future<void> _toggle(NotificationType type, bool value) async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    setState(() {
      _prefs = NotificationPreferences(values: {
        ...?_prefs?.values,
        type: value,
      });
    });
    await widget.service.updatePreference(user.uid, type, value);
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
                    children: NotificationType.values
                        .map(
                          (type) => SwitchListTile(
                            title: Text(_label(type)),
                            value: _prefs![type],
                            onChanged: (val) => _toggle(type, val),
                          ),
                        )
                        .toList(),
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
      case NotificationType.dailyReminder:
        return 'Daily Reading Reminder';
      case NotificationType.comment:
        return 'Comment Notifications';
    }
  }
}
