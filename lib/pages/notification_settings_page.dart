import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/notification_preferences.dart';
import '../services/error_logger.dart';
import '../services/notification_preferences_service.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
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
  bool _reminderEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 7, minute: 0);

  @override
  void initState() {
    super.initState();
    final user = widget.auth.currentUser;
    if (user != null) {
      Future.wait([
        widget.service.fetchPreferences(user.uid),
        widget.service.fetchVibrationEnabled(user.uid),
        ReminderService().loadSettings(),
      ]).then((result) {
        if (mounted) {
          setState(() {
            _prefs = result[0] as NotificationPreferences;
            _vibrationEnabled = result[1] as bool;
            final reminderSettings = result[2] as Map<String, dynamic>;
            _reminderEnabled = reminderSettings['enabled'] as bool;
            _reminderTime = reminderSettings['time'] as TimeOfDay;
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
      _prefs = NotificationPreferences(
        values: {...?_prefs?.values, type: value},
      );
    });
    widget.service.updatePreference(user.uid, type, value).catchError((e, st) {
      ErrorLogger.log(e, st);
      if (!mounted) return;
      setState(() {
        _prefs = NotificationPreferences(
          values: {...?_prefs?.values, type: previous},
        );
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

  Future<void> _toggleReminder(bool value) async {
    setState(() {
      _reminderEnabled = value;
    });
    await ReminderService().saveSettings(value, _reminderTime);
  }

  Future<void> _pickTime() async {
    final newTime = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
    );

    if (newTime != null) {
      setState(() {
        _reminderTime = newTime;
      });
      if (_reminderEnabled) {
        await ReminderService().saveSettings(true, newTime);
      } else {
        // Just save the time preference without scheduling if disabled
        // Actually saveSettings handles scheduling only if enabled.
        await ReminderService().saveSettings(false, newTime);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: CommonStyles.buildAppBar(context, 'Notifications'),
      body: Container(
        decoration: CommonStyles.backgroundDecoration(colorScheme),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_prefs == null
                ? const Center(child: Text('Please sign in'))
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.hPadding,
                      vertical: AppSpacing.gap16,
                    ),
                    children: [
                      _groupedCard(colorScheme, _buildRows(context)),
                      const SizedBox(height: AppSpacing.gap16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'We keep notifications quiet and few — only what '
                          'helps you keep showing up.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colorScheme.outline),
                        ),
                      ),
                    ],
                  )),
      ),
    );
  }

  /// Bordered card grouping all notification rows, separated by dividers.
  Widget _groupedCard(ColorScheme colorScheme, List<Widget> rows) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(Divider(
          height: 1,
          indent: AppSpacing.hPadding,
          endIndent: AppSpacing.hPadding,
          color: colorScheme.outlineVariant,
        ));
      }
      children.add(rows[i]);
    }
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        side: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
      ),
      child: Column(children: children),
    );
  }

  List<Widget> _buildRows(BuildContext context) {
    const rowPadding = EdgeInsets.symmetric(horizontal: AppSpacing.hPadding);
    final rows = <Widget>[
      SwitchListTile(
        contentPadding: rowPadding,
        title: const Text('Daily Reminder'),
        subtitle: Text('A gentle nudge at ${_reminderTime.format(context)}'),
        value: _reminderEnabled,
        onChanged: _toggleReminder,
      ),
    ];
    if (_reminderEnabled) {
      rows.add(ListTile(
        contentPadding: rowPadding,
        title: const Text('Time'),
        trailing: Text(
          _reminderTime.format(context),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        onTap: _pickTime,
      ));
    }
    for (final type in NotificationType.values) {
      final val = _prefs![type];
      rows.add(SwitchListTile(
        contentPadding: rowPadding,
        title: Text(_label(type)),
        value: val,
        onChanged: (v) => _toggle(type, v),
      ));
    }
    rows.add(SwitchListTile(
      contentPadding: rowPadding,
      title: const Text('Vibration'),
      value: _vibrationEnabled,
      onChanged: _toggleVibration,
    ));
    return rows;
  }

  String _label(NotificationType type) {
    switch (type) {
      case NotificationType.like:
        return 'Like Notifications';
      case NotificationType.nudge:
        return 'Nudge Notifications';
      case NotificationType.signup:
        return 'Signup Alerts';
      case NotificationType.friendRequest:
        return 'Friend Request Notifications';
      case NotificationType.comment:
        return 'Comment Notifications';
      case NotificationType.groupJoinRequest:
        return 'Group Join Request Notifications';
      case NotificationType.groupScheduleUpdate:
        return 'Group Schedule Update Notifications';
      case NotificationType.groupInvite:
        return 'Group Invite Notifications';
      case NotificationType.seasonalChallenge:
        return 'Seasonal Challenge Notifications';
    }
  }
}
