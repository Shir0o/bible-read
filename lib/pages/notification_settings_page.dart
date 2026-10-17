import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/skeleton_loader.dart';
import '../widgets/skeletons/list_rows_skeleton.dart';
import '../models/notification_preferences.dart';
import '../services/error_logger.dart';
import '../services/notification_preferences_service.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_styles.dart';
import '../widgets/sub_header.dart';

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
  bool _loadFailed = false;
  bool _vibrationEnabled = true;
  bool _reminderEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 7, minute: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads every setting the page shows. A failure ends in a retryable
  /// error state rather than an endless spinner.
  Future<void> _load() async {
    final user = widget.auth.currentUser;
    if (user == null) {
      _loading = false;
      return;
    }
    try {
      final result = await Future.wait([
        widget.service.fetchPreferences(user.uid),
        widget.service.fetchVibrationEnabled(user.uid),
        ReminderService().loadSettings(),
      ]);
      if (!mounted) return;
      setState(() {
        _prefs = result[0] as NotificationPreferences;
        _vibrationEnabled = result[1] as bool;
        final reminderSettings = result[2] as Map<String, dynamic>;
        _reminderEnabled = reminderSettings['enabled'] as bool;
        _reminderTime = reminderSettings['time'] as TimeOfDay;
        _loading = false;
      });
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    _load();
  }

  Widget _buildLoadError(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: AppSpacing.horizontal,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Couldn't load your notification settings.",
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.gap12),
            TextButton(onPressed: _retry, child: const Text('Try again')),
          ],
        ),
      ),
    );
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
    // SubHeader, like Settings, which this page is opened from.
    return Scaffold(
      body: Container(
        decoration: CommonStyles.backgroundDecoration(colorScheme),
        child: SafeArea(
          child: Column(
            children: [
              SubHeader(
                title: 'Notifications',
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Expanded(child: _buildBody(context, colorScheme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme colorScheme) {
    if (_loadFailed) return _buildLoadError(context, colorScheme);
    return SkeletonLoader(
        loading: _loading,
        skeleton: const ListRowsSkeleton(count: 6, showAvatar: false),
        child: (_prefs == null
            ? const Center(child: Text('Please sign in'))
            : ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.hPadding,
                  vertical: AppSpacing.gap16,
                ),
                children: [
                  _groupedCard(context, _buildRows(context)),
                  const SizedBox(height: AppSpacing.gap16),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.gap8),
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
              )));
  }

  /// Bordered card grouping all notification rows, separated by dividers.
  Widget _groupedCard(BuildContext context, List<Widget> rows) {
    final colorScheme = Theme.of(context).colorScheme;
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(
          Divider(
            height: 1,
            indent: AppSpacing.hPadding,
            endIndent: AppSpacing.hPadding,
            color: colorScheme.outlineVariant,
          ),
        );
      }
      children.add(rows[i]);
    }
    return CommonStyles.buildBorderedCard(
      context: context,
      child: Column(children: children),
    );
  }

  List<Widget> _buildRows(BuildContext context) {
    const rowPadding = EdgeInsets.symmetric(horizontal: AppSpacing.hPadding);
    final rows = <Widget>[
      SwitchListTile(
        contentPadding: rowPadding,
        title: const Text('Daily reminder'),
        subtitle: Text(
          _reminderEnabled
              ? 'A gentle nudge at ${_reminderTime.format(context)}'
              : 'Get a gentle nudge to read each day',
        ),
        value: _reminderEnabled,
        onChanged: _toggleReminder,
      ),
    ];
    if (_reminderEnabled) {
      rows.add(
        ListTile(
          contentPadding: rowPadding,
          title: const Text('Time'),
          trailing: Text(
            _reminderTime.format(context),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          onTap: _pickTime,
        ),
      );
    }
    for (final type in NotificationType.values) {
      final val = _prefs![type];
      rows.add(
        SwitchListTile(
          contentPadding: rowPadding,
          title: Text(_label(type)),
          value: val,
          onChanged: (v) => _toggle(type, v),
        ),
      );
    }
    rows.add(
      SwitchListTile(
        contentPadding: rowPadding,
        title: const Text('Vibration'),
        value: _vibrationEnabled,
        onChanged: _toggleVibration,
      ),
    );
    return rows;
  }

  String _label(NotificationType type) {
    switch (type) {
      case NotificationType.amen:
        return 'Amens';
      case NotificationType.nudge:
        return 'Nudges';
      case NotificationType.signup:
        return 'Signup alerts';
      case NotificationType.groupJoinRequest:
        return 'Group join requests';
      case NotificationType.groupScheduleUpdate:
        return 'Group schedule changes';
      case NotificationType.groupInvite:
        return 'Group invites';
      case NotificationType.seasonalChallenge:
        return 'Seasonal challenges';
      case NotificationType.badge:
        return 'Badges';
    }
  }
}
