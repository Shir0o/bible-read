import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import 'app_bottom_sheet.dart';
import 'common_styles.dart';

/// The pre-join preview for a public Group.
///
/// A non-member is allowed to see the Group's name, what it is reading, and
/// its member count. Nothing else. Member names, photos, and daily
/// Progress stay behind the join-request approval gate (ADR-0003), so this
/// widget never reads or renders member data. It is a sheet rather than a
/// page so non-members never get a full Group screen.
class GroupPreviewSheet extends StatefulWidget {
  /// The public Group being previewed.
  final Group group;

  /// Service used to send the join request.
  final GroupService groupService;

  /// Authentication used to identify the requesting reader.
  final FirebaseAuth auth;

  /// Haptics for interactions.
  final VibrationService vibrationService;

  const GroupPreviewSheet({
    super.key,
    required this.group,
    required this.groupService,
    required this.auth,
    required this.vibrationService,
  });

  /// Opens this preview in the app's standard bottom-sheet chrome.
  static Future<void> show({
    required BuildContext context,
    required Group group,
    required GroupService groupService,
    required FirebaseAuth auth,
    required VibrationService vibrationService,
  }) {
    return showAppSheet<void>(
      context: context,
      builder: (_) => GroupPreviewSheet(
        group: group,
        groupService: groupService,
        auth: auth,
        vibrationService: vibrationService,
      ),
    );
  }

  /// A short, non-member-safe description of what the Group is reading.
  ///
  /// Prefers the persisted plan books. Groups created before `planConfig`
  /// existed still get an honest fallback rather than exposing their
  /// schedule or members.
  static String readingLabel(Group group) {
    final books = group.planConfig?.books ?? const <String>[];
    if (books.isEmpty) return 'Bible reading plan';
    if (books.length == 1) return 'Reading ${books.first}';
    return 'Reading ${books.first} +${books.length - 1} more';
  }

  @override
  State<GroupPreviewSheet> createState() => _GroupPreviewSheetState();
}

class _GroupPreviewSheetState extends State<GroupPreviewSheet> {
  bool _requesting = false;

  Future<void> _requestToJoin() async {
    final user = widget.auth.currentUser;
    if (user == null || _requesting) return;

    unawaited(widget.vibrationService.lightImpact());
    setState(() => _requesting = true);

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.groupService.requestJoin(
        groupId: widget.group.id,
        uid: user.uid,
        name: user.displayName ?? '',
        photoUrl: user.photoURL,
      );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Request sent to ${widget.group.name}'),
        ),
      );
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      if (!mounted) return;
      setState(() => _requesting = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to send request')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final memberCount = widget.group.memberCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.hPadding,
        4,
        AppSpacing.hPadding,
        AppSpacing.gap24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PublicGroupBadge(colorScheme: colorScheme),
          const SizedBox(height: AppSpacing.gap12),
          Text(
            widget.group.name,
            style: AppTextStyles.title(context).copyWith(
              fontFamily: AppTheme.fontSerif,
              fontSize: 24,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: AppSpacing.gap20),
          _PreviewDetailRow(
            icon: Icons.menu_book_outlined,
            text: GroupPreviewSheet.readingLabel(widget.group),
          ),
          const SizedBox(height: AppSpacing.gap12),
          _PreviewDetailRow(
            icon: Icons.group_outlined,
            text: memberCount == 1 ? '1 member' : '$memberCount members',
          ),
          const SizedBox(height: AppSpacing.gap12),
          const _PreviewDetailRow(
            icon: Icons.verified_user_outlined,
            text: 'A member approves new readers',
          ),
          const SizedBox(height: AppSpacing.gap20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.gap16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppSpacing.rInset),
              border: Border.all(color: AppColors.of(context).border),
            ),
            child: Text(
              "Members' names and daily progress stay hidden until someone "
              'approves you - and yours becomes visible to them at the same '
              'moment.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.gap24),
          SizedBox(
            width: double.infinity,
            height: AppSpacing.buttonHeight,
            child: FilledButton(
              onPressed: _requesting ? null : _requestToJoin,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.rButton),
                ),
                textStyle: const TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: _requesting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : const Text('Request to join'),
            ),
          ),
          const SizedBox(height: AppSpacing.gap8),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton(
              onPressed: _requesting ? null : () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurfaceVariant,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.rButton),
                ),
                textStyle: const TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Not now'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicGroupBadge extends StatelessWidget {
  final ColorScheme colorScheme;

  const _PublicGroupBadge({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        'Public group',
        style: TextStyle(
          color: colorScheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          fontFamily: AppTheme.fontUi,
        ),
      ),
    );
  }
}

class _PreviewDetailRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PreviewDetailRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 19, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.gap12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 15,
                ),
          ),
        ),
      ],
    );
  }
}
