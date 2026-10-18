import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/error_logger.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../services/join_code_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/sub_header.dart';
import '../widgets/join_code_keys.dart';
import '../widgets/friend_code_keys.dart';
import '../theme/app_theme.dart';

/// Redeems a code: the reader types it, previews who or which group it lands
/// in, and joins — directly for public groups, as a join request otherwise.
/// Eight-character codes are Friend codes; six-character codes are Group
/// join codes, so one field serves both (ADR-0012).
class JoinByCodePage extends StatefulWidget {
  /// Service used to resolve codes and join the group.
  final GroupService groupService;

  /// Auth used for the joining reader.
  final FirebaseAuth auth;

  /// Haptics for interactions.
  final VibrationService vibrationService;

  /// Friend code operations. Defaults lazily so group-only flows never touch
  /// Firebase beyond the injected GroupService.
  final FriendService? friendService;

  /// Creates a [JoinByCodePage].
  JoinByCodePage({
    super.key,
    GroupService? groupService,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
    this.friendService,
  })  : groupService = groupService ?? GroupService(),
        auth = auth ?? FirebaseAuth.instance,
        vibrationService = vibrationService ?? const VibrationService();

  @override
  State<JoinByCodePage> createState() => _JoinByCodePageState();
}

class _JoinByCodePageState extends State<JoinByCodePage> {
  final TextEditingController _controller = TextEditingController();
  JoinCodeMatch? _match;
  FriendCodeMatch? _friendMatch;
  String? _error;
  bool _lookingUp = false;
  bool _joining = false;

  /// Built only when an eight-character code needs it, so the group flow
  /// never depends on a Firebase singleton in tests.
  late final FriendService _friendService =
      widget.friendService ?? FriendService();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _findCode() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    unawaited(widget.vibrationService.lightImpact());

    final raw = _controller.text;
    if (raw.trim().isEmpty) {
      setState(() {
        _match = null;
        _friendMatch = null;
        _error = 'Enter the code that was shared with you.';
      });
      return;
    }

    final code = FriendService.normalize(raw);
    if (code.length != JoinCodeService.codeLength &&
        code.length != FriendService.codeLength) {
      setState(() {
        _match = null;
        _friendMatch = null;
        _error = 'Codes are 6 characters for a group or 8 for a friend.';
      });
      return;
    }

    setState(() {
      _lookingUp = true;
      _match = null;
      _friendMatch = null;
      _error = null;
    });

    if (code.length == FriendService.codeLength) {
      await _findFriend(raw, uid);
    } else {
      await _findGroup(raw, uid);
    }
  }

  Future<void> _findFriend(String raw, String uid) async {
    try {
      final match = await _friendService.resolve(raw, uid);
      if (!mounted) return;
      setState(() {
        _lookingUp = false;
        if (match == null) {
          _error = "We couldn't find anyone with that code. Check it and try "
              'again.';
        } else if (match.isSelf) {
          _error = "That's your own code. Share it with someone instead.";
        } else if (match.isFriend) {
          _error = 'You’re already friends with '
              '${_displayName(match.name)}.';
        } else {
          _friendMatch = match;
        }
      });
    } catch (e, st) {
      unawaited(ErrorLogger.log(e, st));
      if (!mounted) return;
      setState(() {
        _lookingUp = false;
        _error = 'Something went wrong. Try again.';
      });
    }
  }

  Future<void> _findGroup(String raw, String uid) async {
    try {
      final match = await widget.groupService.joinCodeService.resolve(raw, uid);
      if (!mounted) return;
      setState(() {
        _lookingUp = false;
        if (match == null) {
          _error =
              "We couldn't find a group with that code. Check it and try again.";
        } else {
          _match = match;
        }
      });
    } catch (e, st) {
      unawaited(ErrorLogger.log(e, st));
      if (!mounted) return;
      setState(() {
        _lookingUp = false;
        _error = 'Something went wrong. Try again.';
      });
    }
  }

  static String _displayName(String? name) {
    final trimmed = name?.trim() ?? '';
    return trimmed.isEmpty ? 'them' : trimmed;
  }

  Future<void> _confirmFriend() async {
    final user = widget.auth.currentUser;
    final match = _friendMatch;
    if (user == null || match == null) return;
    unawaited(widget.vibrationService.lightImpact());

    setState(() => _joining = true);
    try {
      final result = await _friendService.redeem(match.code);
      if (!mounted) return;
      switch (result) {
        case FriendRedemption.added:
          final name = _displayName(match.name);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('You’re now friends with $name')),
          );
          Navigator.of(context).maybePop();
        case FriendRedemption.self:
          setState(() {
            _joining = false;
            _friendMatch = null;
            _error = "That's your own code. Share it with someone instead.";
          });
        case FriendRedemption.alreadyFriends:
          setState(() {
            _joining = false;
            _friendMatch = null;
            _error = 'You’re already friends with '
                '${_displayName(match.name)}.';
          });
        case FriendRedemption.unknown:
          setState(() {
            _joining = false;
            _friendMatch = null;
            _error = 'That code no longer works. Check it and try again.';
          });
      }
    } catch (e, st) {
      unawaited(ErrorLogger.log(e, st));
      if (!mounted) return;
      setState(() => _joining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Try again.')),
      );
    }
  }

  Future<void> _confirmJoin() async {
    final user = widget.auth.currentUser;
    final match = _match;
    if (user == null || match == null || match.isMember) return;
    unawaited(widget.vibrationService.lightImpact());

    setState(() => _joining = true);
    try {
      await widget.groupService.joinGroup(
        groupId: match.group.id,
        uid: user.uid,
        name: user.displayName ?? '',
        photoUrl: user.photoURL,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            match.group.isPublic
                ? 'You joined ${match.group.name}'
                : 'Request sent to ${match.group.name}',
          ),
        ),
      );
    } catch (e, st) {
      unawaited(ErrorLogger.log(e, st));
      if (!mounted) return;
      setState(() => _joining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Try again.')),
      );
    }
  }

  String _memberCountText(int count) {
    if (count == 1) return '1 member';
    return '$count members';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            SubHeader(
              title: 'Enter a code',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Container(
                decoration: CommonStyles.backgroundDecoration(colorScheme),
                child: SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.gap16),
                    children: [
                      TextField(
                        key: JoinCodeKeys.codeField,
                        controller: _controller,
                        textCapitalization: TextCapitalization.characters,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _findCode(),
                        decoration: const InputDecoration(
                          labelText: 'Code',
                          hintText: 'Group or friend code',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.gap16),
                      FilledButton(
                        key: JoinCodeKeys.findButton,
                        onPressed: _lookingUp ? null : _findCode,
                        child: _lookingUp
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  // token-exempt: button submitting
                                  strokeWidth: 2,
                                  color: colorScheme.onPrimary,
                                ),
                              )
                            : const Text('Find'),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.gap12),
                        Text(
                          _error!,
                          key: JoinCodeKeys.errorText,
                          style: AppTextStyles.bodySmall(context).copyWith(
                            color: colorScheme.error,
                          ),
                        ),
                      ],
                      if (_friendMatch != null) ...[
                        const SizedBox(height: AppSpacing.gap24),
                        KeyedSubtree(
                          key: FriendCodeKeys.previewCard,
                          child: CommonStyles.buildCard(
                            context: context,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _FriendAvatar(
                                      name: _friendMatch!.name,
                                      photoUrl: _friendMatch!.photoUrl,
                                    ),
                                    const SizedBox(width: AppSpacing.gap12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _displayName(_friendMatch!.name),
                                            style: AppTextStyles.title(context)
                                                .copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(
                                              height: AppSpacing.gap2),
                                          Text(
                                            'Friend code',
                                            style:
                                                AppTextStyles.bodySmall(context)
                                                    .copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.check_rounded,
                                      color: colorScheme.primary,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.gap16),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    key: FriendCodeKeys.confirmButton,
                                    onPressed: _joining ? null : _confirmFriend,
                                    child: Text(
                                      'Add ${_displayName(_friendMatch!.name)} '
                                      'as a friend',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.gap8),
                                Text(
                                  'You’ll each see the other in Circle — when '
                                  'they show up, what they share, and the '
                                  'Badges they earn. Either of you can '
                                  'unfriend at any time.',
                                  style:
                                      AppTextStyles.bodySmall(context).copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (_match != null) ...[
                        const SizedBox(height: AppSpacing.gap24),
                        KeyedSubtree(
                          key: JoinCodeKeys.previewCard,
                          child: CommonStyles.buildCard(
                            context: context,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _match!.group.name,
                                  style: AppTextStyles.title(context).copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.gap4),
                                Text(
                                  _memberCountText(_match!.group.memberCount),
                                  style:
                                      AppTextStyles.bodySmall(context).copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (_match!.isMember) ...[
                                  const SizedBox(height: AppSpacing.gap12),
                                  Text(
                                    "You're already in this group",
                                    key: JoinCodeKeys.memberNote,
                                    style: AppTextStyles.bodySmall(context)
                                        .copyWith(
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ] else ...[
                                  const SizedBox(height: AppSpacing.gap16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      key: JoinCodeKeys.confirmButton,
                                      onPressed: _joining ? null : _confirmJoin,
                                      child: Text(
                                        _match!.group.isPublic
                                            ? 'Join group'
                                            : 'Ask to join',
                                      ),
                                    ),
                                  ),
                                  if (!_match!.group.isPublic) ...[
                                    const SizedBox(height: AppSpacing.gap8),
                                    Text(
                                      'An owner will approve your request before '
                                      "you're in.",
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small avatar for the friend preview card.
class _FriendAvatar extends StatelessWidget {
  final String? name;
  final String? photoUrl;

  const _FriendAvatar({this.name, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initial = (name?.trim().isNotEmpty ?? false)
        ? name!.trim().substring(0, 1).toUpperCase()
        : '?';
    return CircleAvatar(
      radius: 22,
      backgroundColor: colorScheme.secondaryContainer,
      foregroundImage: (photoUrl != null && photoUrl!.isNotEmpty)
          ? NetworkImage(photoUrl!)
          : null,
      child: Text(
        initial,
        style: TextStyle(
          color: colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
