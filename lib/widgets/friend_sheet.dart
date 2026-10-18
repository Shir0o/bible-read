import 'dart:async';

import 'package:flutter/material.dart';

import '../models/circle_member.dart';
import '../services/error_logger.dart';
import '../services/friend_service.dart';
import '../services/nudge_service.dart';
import '../services/read_log_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import 'app_bottom_sheet.dart';
import 'common_styles.dart';

/// A Friend's sheet: who they are, how long you have been Friends, their
/// week, a Nudge and Unfriend. Unfriending is silent and ends the connection
/// for both readers; a shared Group keeps them in the Circle.
Future<void> showFriendSheet(
  BuildContext context, {
  required CircleMember friend,
  required List<String> sharedGroupNames,
  required Set<String> shownUpDateKeys,
  required String? reading,
  required FriendService friendService,
  required NudgeService nudgeService,
  required VibrationService vibrationService,
  required String myUid,
  required String myName,
  required DateTime today,
}) {
  return showAppSheet<void>(
    context: context,
    builder: (_) => _FriendSheet(
      friend: friend,
      sharedGroupNames: sharedGroupNames,
      shownUpDateKeys: shownUpDateKeys,
      reading: reading,
      friendService: friendService,
      nudgeService: nudgeService,
      vibrationService: vibrationService,
      myUid: myUid,
      myName: myName,
      today: today,
    ),
  );
}

class _FriendSheet extends StatefulWidget {
  final CircleMember friend;
  final List<String> sharedGroupNames;
  final Set<String> shownUpDateKeys;
  final String? reading;
  final FriendService friendService;
  final NudgeService nudgeService;
  final VibrationService vibrationService;
  final String myUid;
  final String myName;
  final DateTime today;

  const _FriendSheet({
    required this.friend,
    required this.sharedGroupNames,
    required this.shownUpDateKeys,
    required this.reading,
    required this.friendService,
    required this.nudgeService,
    required this.vibrationService,
    required this.myUid,
    required this.myName,
    required this.today,
  });

  @override
  State<_FriendSheet> createState() => _FriendSheetState();
}

class _FriendSheetState extends State<_FriendSheet> {
  bool _unfriending = false;
  bool _nudging = false;

  String get _name {
    final name = (widget.friend.name ?? '').trim();
    return name.isEmpty ? 'This reader' : name.split(' ').first;
  }

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String? get _sinceLabel {
    final since = widget.friend.friendSince;
    if (since == null) return null;
    return 'since ${since.day} ${_months[since.month - 1]}';
  }

  String get _unfriendCopy {
    if (widget.sharedGroupNames.isEmpty) {
      return '$_name won’t be told. You don’t share a group, so they’ll leave '
          'your Circle.';
    }
    final groups = widget.sharedGroupNames.join(', ');
    return '$_name won’t be told. You share $groups, so they’ll stay in your '
        'Circle.';
  }

  Future<void> _nudge() async {
    if (_nudging) return;
    widget.vibrationService.lightImpact();
    setState(() => _nudging = true);
    try {
      final result = await widget.nudgeService.nudgeMember(
        currentUid: widget.myUid,
        memberUid: widget.friend.uid,
        currentName: widget.myName,
      );
      if (!mounted) return;
      final message = switch (result) {
        NudgeResult.sent => 'Nudge sent',
        NudgeResult.alreadySent => 'You already nudged them today',
        NudgeResult.alreadyRead => 'They’ve already shown up today',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (e, st) {
      unawaited(ErrorLogger.log(e, st));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn’t send the nudge. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _nudging = false);
    }
  }

  Future<void> _unfriend() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Unfriend $_name?'),
        content: Text(_unfriendCopy),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Unfriend'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _unfriending = true);
    try {
      await widget.friendService.unfriend(widget.friend.uid);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('You’re no longer friends with $_name')),
      );
    } catch (e, st) {
      unawaited(ErrorLogger.log(e, st));
      if (!mounted) return;
      setState(() => _unfriending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn’t unfriend them. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final since = _sinceLabel;
    final week = _week(widget.today);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.hPadding, AppSpacing.gap12,
          AppSpacing.hPadding, AppSpacing.gap24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Column(
              children: [
                _Avatar(
                    name: _name, photoUrl: widget.friend.photoUrl, size: 72),
                const SizedBox(height: AppSpacing.gap8),
                Text(
                  _name,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.gap4),
                Wrap(
                  spacing: AppSpacing.gap8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.gap8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(AppSpacing.rChip),
                      ),
                      child: Text(
                        'Friend',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    if (since != null)
                      Text(
                        since,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.gap16),
          CommonStyles.buildCard(
            context: context,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.gap16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'THIS WEEK',
                    style: AppTextStyles.caption(context).copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.gap12),
                  Row(
                    children: [
                      for (final day in week)
                        Expanded(
                          child: Container(
                            height: 30,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: day.shownUp
                                  ? colorScheme.primary
                                  : colorScheme.surfaceContainerHighest,
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.rChip),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.gap12),
                  Text(
                    'Shown up ${week.where((d) => d.shownUp).length} of 7 days'
                    '${widget.reading == null ? '' : ' · Reading ${widget.reading}'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.gap16),
          FilledButton.icon(
            onPressed: _nudging ? null : _nudge,
            icon: const Icon(Icons.north_rounded, size: 16),
            label: Text('Nudge $_name'),
          ),
          const SizedBox(height: AppSpacing.gap8),
          TextButton(
            onPressed: _unfriending ? null : _unfriend,
            style: TextButton.styleFrom(
              // token-exempt: destructive text action
              foregroundColor: colorScheme.error,
            ),
            child: _unfriending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      // token-exempt: inline button progress
                      strokeWidth: 2,
                    ),
                  )
                : const Text('Unfriend'),
          ),
          Text(
            _unfriendCopy,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.outline,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<({String dateKey, bool shownUp})> _week(DateTime today) {
    return [
      for (var i = 6; i >= 0; i--)
        () {
          final date = DateTime(today.year, today.month, today.day - i);
          final key = ReadLogService.dateKeyFor(date);
          return (dateKey: key, shownUp: widget.shownUpDateKeys.contains(key));
        }(),
    ];
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double size;

  const _Avatar(
      {required this.name, required this.photoUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initial =
        name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: colorScheme.secondaryContainer,
      foregroundImage: (photoUrl != null && photoUrl!.isNotEmpty)
          ? NetworkImage(photoUrl!)
          : null,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
