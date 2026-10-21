import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/group.dart';
import '../services/error_logger.dart';
import '../services/friend_invite.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_styles.dart';
import '../widgets/skeleton.dart';
import '../widgets/skeleton_loader.dart';

/// The step right after creating a group plan: invite people with the
/// group's link or code before landing in the group.
class GroupInvitePage extends StatefulWidget {
  /// The group just created.
  final Group group;

  /// Service used to read the group's join code.
  final GroupService groupService;

  /// Haptics for interactions.
  final VibrationService vibrationService;

  /// Leaves the invite step for the group itself.
  final VoidCallback onDone;

  const GroupInvitePage({
    super.key,
    required this.group,
    required this.groupService,
    required this.onDone,
    this.vibrationService = const VibrationService(),
  });

  @override
  State<GroupInvitePage> createState() => _GroupInvitePageState();
}

class _GroupInvitePageState extends State<GroupInvitePage> {
  String? _code;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadCode();
  }

  Future<void> _loadCode() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final code = await widget.groupService.joinCodeService
          .ensureGroupCode(widget.group.id);
      if (!mounted) return;
      setState(() {
        _code = code;
        _loading = false;
      });
    } catch (e, st) {
      unawaited(ErrorLogger.log(e, st));
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _shareLink() async {
    final code = _code;
    if (code == null) return;
    unawaited(widget.vibrationService.lightImpact());
    await SharePlus.instance.share(ShareParams(
      text: 'Join my group "${widget.group.name}" on Bible Reading Challenge: '
          '${FriendInvite.linkFor(code)}',
    ));
  }

  Future<void> _copyCode() async {
    final code = _code;
    if (code == null) return;
    unawaited(widget.vibrationService.lightImpact());
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.hPadding,
            AppSpacing.gap40,
            AppSpacing.hPadding,
            AppSpacing.gap16,
          ),
          children: [
            Center(
              child: CircleAvatar(
                radius: 28,
                backgroundColor: colorScheme.secondaryContainer,
                child: Icon(
                  Icons.person_add_alt_1_rounded,
                  color: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.gap12),
            Text(
              '${widget.group.name} is ready',
              style: AppTextStyles.topBarTitle(context).copyWith(fontSize: 28),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.gap8),
            Text(
              'Invite people to read the same schedule with you.',
              style: AppTextStyles.body(context).copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.gap24),
            CommonStyles.buildCard(
              context: context,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: SkeletonLoader(
                  loading: _loading,
                  skeleton: const Column(
                    children: [
                      Skeleton(width: double.infinity, height: 48),
                      SizedBox(height: AppSpacing.gap16),
                      Skeleton(width: double.infinity, height: 40),
                    ],
                  ),
                  child: _loading
                      ? const SizedBox.shrink()
                      : _buildInviteCard(context),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.hPadding,
            AppSpacing.gap12,
            AppSpacing.hPadding,
            AppSpacing.gap12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  key: const Key('group_invite_done'),
                  onPressed: widget.onDone,
                  child: const Text('Go to group'),
                ),
              ),
              const SizedBox(height: AppSpacing.gap8),
              Text(
                'You can invite people any time from the group page.',
                style: AppTextStyles.bodySmall(context).copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInviteCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_failed) {
      return Column(
        children: [
          Text(
            'Could not load the invite. Check your connection.',
            style: AppTextStyles.body(context).copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          TextButton(onPressed: _loadCode, child: const Text('Try again')),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('group_invite_share'),
          onPressed: _shareLink,
          icon: const Icon(Icons.ios_share_rounded, size: 18),
          label: const Text('Share invite link'),
        ),
        const SizedBox(height: AppSpacing.gap16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Or share the code',
                    style: AppTextStyles.bodySmall(context).copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    _code!,
                    key: const Key('group_invite_code'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: _copyCode,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy'),
            ),
          ],
        ),
      ],
    );
  }
}
