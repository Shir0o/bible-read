import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/error_logger.dart';
import '../services/friend_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_styles.dart';
import '../widgets/friend_avatar.dart';
import '../widgets/friend_code_keys.dart';
import '../widgets/friend_redeem.dart';

/// What the invite is showing: the confirm card, or one of the ways it can
/// fail. The invite never adds anyone by itself — only the Add button does.
enum _InviteState { loading, found, invalid, self, alreadyFriends, signedOut }

/// The one screen an invite link opens: "{Name} invited you", with Add and
/// Not now (ADR-0012 V3). The link carries only the code; the name and photo
/// are resolved here through [FriendService].
class FriendInvitePage extends StatefulWidget {
  /// The friend code carried by the link.
  final String code;

  /// Auth used for the recipient.
  final FirebaseAuth auth;

  /// Code operations: resolving the inviter and redeeming on Add.
  final FriendService friendService;

  /// Haptics for interactions.
  final VibrationService vibrationService;

  /// Creates a [FriendInvitePage].
  FriendInvitePage({
    super.key,
    required this.code,
    FirebaseAuth? auth,
    FriendService? friendService,
    VibrationService? vibrationService,
  })  : auth = auth ?? FirebaseAuth.instance,
        friendService = friendService ?? FriendService(),
        vibrationService = vibrationService ?? const VibrationService();

  @override
  State<FriendInvitePage> createState() => _FriendInvitePageState();
}

class _FriendInvitePageState extends State<FriendInvitePage> {
  _InviteState _state = _InviteState.loading;
  FriendCodeMatch? _match;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) {
      if (!mounted) return;
      setState(() => _state = _InviteState.signedOut);
      return;
    }

    setState(() => _state = _InviteState.loading);
    try {
      final match = await widget.friendService.resolve(widget.code, uid);
      if (!mounted) return;
      setState(() {
        if (match == null) {
          _state = _InviteState.invalid;
        } else if (match.isSelf) {
          _state = _InviteState.self;
        } else if (match.isFriend) {
          _state = _InviteState.alreadyFriends;
          _match = match;
        } else {
          _state = _InviteState.found;
          _match = match;
        }
      });
    } catch (e, st) {
      unawaited(ErrorLogger.log(e, st));
      if (!mounted) return;
      setState(() => _state = _InviteState.invalid);
    }
  }

  String _displayName(String? name) {
    final trimmed = name?.trim() ?? '';
    return trimmed.isEmpty ? 'them' : trimmed;
  }

  void _notNow() {
    unawaited(widget.vibrationService.lightImpact());
    Navigator.of(context).maybePop();
  }

  Future<void> _add() async {
    final match = _match;
    if (match == null) return;
    unawaited(widget.vibrationService.lightImpact());

    setState(() => _adding = true);
    final result = await redeemFriendCode(
      context,
      friendService: widget.friendService,
      code: widget.code,
      displayName: _displayName(match.name),
    );
    if (!mounted || result == FriendRedemption.added) return;
    setState(() {
      _adding = false;
      _state = switch (result) {
        FriendRedemption.self => _InviteState.self,
        FriendRedemption.alreadyFriends => _InviteState.alreadyFriends,
        FriendRedemption.unknown => _InviteState.invalid,
        _ => _state,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gap24,
            vertical: AppSpacing.gap20,
          ),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_state == _InviteState.loading) {
      return const Center(
        child: CircularProgressIndicator(
            // token-exempt: resolving the invite before it can be shown
            ),
      );
    }
    if (_state == _InviteState.found) return _buildFound(context);
    return _buildMessage(context);
  }

  Widget _buildFound(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final match = _match!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        _InviteAvatars(
          inviterName: match.name,
          inviterPhotoUrl: match.photoUrl,
          viewerName: widget.auth.currentUser?.displayName,
        ),
        const SizedBox(height: AppSpacing.gap24),
        Text(
          '${_displayName(match.name)} invited you',
          style: AppTextStyles.title(context),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.gap8),
        Text(
          'Be friends and you’ll see each other in Circle — when you show up, '
          'what you share, the Badges you earn.',
          style: AppTextStyles.body(context).copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const Spacer(flex: 2),
        FilledButton(
          key: FriendCodeKeys.inviteAddButton,
          onPressed: _adding ? null : _add,
          child: _adding
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    // token-exempt: button submitting
                    strokeWidth: 2,
                    color: colorScheme.onPrimary,
                  ),
                )
              : Text('Add ${_displayName(match.name)} as a friend'),
        ),
        TextButton(
          key: FriendCodeKeys.inviteNotNow,
          onPressed: _adding ? null : _notNow,
          child: const Text('Not now'),
        ),
        Text(
          'Either of you can unfriend at any time.',
          style: AppTextStyles.bodySmall(context).copyWith(
            color: colorScheme.outline,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildMessage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (title, body) = switch (_state) {
      _InviteState.invalid => (
          'This invite no longer works',
          'The code may have been reset. Ask your friend for a new link.',
        ),
      _InviteState.self => (
          'That’s your own invite link',
          'Share it with someone instead — they can add you with it.',
        ),
      _InviteState.alreadyFriends => (
          'You’re already friends with ${_displayName(_match?.name)}.',
          'You’ll see each other in Circle.',
        ),
      _InviteState.signedOut => (
          'Sign in to add this friend',
          'Open Bible Read and sign in, then use the link again.',
        ),
      _ => ('This invite no longer works', 'Ask your friend for a new link.'),
    };

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.link_off_rounded,
          size: 48,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: AppSpacing.gap16),
        Text(
          title,
          key: FriendCodeKeys.inviteError,
          style: AppTextStyles.title(context),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.gap8),
        Text(
          body,
          style: AppTextStyles.body(context).copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.gap24),
        TextButton(
          key: FriendCodeKeys.inviteNotNow,
          onPressed: _notNow,
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// The inviter and recipient avatars, overlapped, as drawn in V3.
class _InviteAvatars extends StatelessWidget {
  final String? inviterName;
  final String? inviterPhotoUrl;
  final String? viewerName;

  const _InviteAvatars({
    this.inviterName,
    this.inviterPhotoUrl,
    this.viewerName,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FriendAvatar(name: inviterName, photoUrl: inviterPhotoUrl, radius: 42),
        Transform.translate(
          offset: const Offset(-16, 0),
          child: FriendAvatar(name: viewerName, radius: 42),
        ),
      ],
    );
  }
}
