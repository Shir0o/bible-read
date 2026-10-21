import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/error_logger.dart';
import '../services/friend_invite.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../services/join_code_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/friend_avatar.dart';
import '../widgets/friend_code_keys.dart';
import '../widgets/friend_redeem.dart';
import '../widgets/join_code_keys.dart';
import '../widgets/qr_scan_view.dart';
import '../widgets/sub_header.dart';
import '../theme/app_theme.dart';

/// The combined add side of "Add a friend" (ADR-0012 V4): a scanner and a code
/// field on one screen, so whatever the reader was handed — a scanned payload,
/// a typed code, or a pasted link — goes in one place.
///
/// Redeems a code: the reader previews who or which group it lands in, and
/// joins — directly for public groups, as a join request otherwise.
/// Eight-character codes are Friend codes; six-character codes are Group
/// join codes, so one field serves both.
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

  /// Header title. The friend add side reads "Their code".
  final String title;

  /// Camera scanner shown above the code field. When null the screen is
  /// field-only; tests inject a fake so no camera is needed.
  final QrScanViewBuilder? scanViewBuilder;

  /// A code to resolve immediately on open (e.g. from an incoming deep link).
  final String? initialCode;

  /// Creates a [JoinByCodePage].
  JoinByCodePage({
    super.key,
    GroupService? groupService,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
    this.friendService,
    this.initialCode,
    this.title = 'Enter a code',
    this.scanViewBuilder,
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

  /// Inline message under the scanner when a payload is not a code.
  String? _scanError;

  /// True while the scanner should ignore detections: from the moment a
  /// payload is routed until its QR has been out of frame for a moment, so
  /// returning from the confirm screen does not immediately re-open it.
  bool _scanPaused = false;

  /// Resumes scanning once detections stop arriving (the code left the frame).
  Timer? _scanIdle;

  /// Built only when an eight-character code needs it, so the group flow
  /// never depends on a Firebase singleton in tests.
  late final FriendService _friendService =
      widget.friendService ?? FriendService();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCode;
    if (initial != null && initial.trim().isNotEmpty) {
      _controller.text = initial.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _findCode();
      });
    }
  }

  @override
  void dispose() {
    _scanIdle?.cancel();
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

    // A pasted invite link carries an invite code; a bare code is normalised
    // and told apart by length (6 = group, 8 = friend).
    final linkedCode = FriendInvite.codeFromText(raw);
    final isFriend =
        linkedCode != null && linkedCode.length == FriendService.codeLength;
    final code = linkedCode ?? FriendService.normalize(raw);
    if (!isFriend && code.length != JoinCodeService.codeLength) {
      setState(() {
        _match = null;
        _friendMatch = null;
        // Eight characters is the right length for a friend code, so the
        // only way to get here with eight is a character outside the
        // alphabet.
        _error = code.length == FriendService.codeLength
            ? "That's not a valid friend code. Check it and try again."
            : 'Codes are 6 characters for a group or 8 for a friend.';
      });
      return;
    }

    setState(() {
      _lookingUp = true;
      _match = null;
      _friendMatch = null;
      _error = null;
    });

    if (isFriend) {
      await _findFriend(code, uid);
    } else {
      await _findGroup(code, uid);
    }
  }

  Future<void> _findFriend(String code, String uid) async {
    try {
      final match = await _friendService.resolve(code, uid);
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

  Future<void> _findGroup(String code, String uid) async {
    try {
      final match =
          await widget.groupService.joinCodeService.resolve(code, uid);
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

  /// Routes a scanned payload like the field: an invite link or a bare code,
  /// six characters to the group flow, eight to the friend flow.
  Future<void> _onScanned(String raw) async {
    if (!mounted) return;
    if (_scanPaused) {
      // A code is still in frame — keep the scanner paused until it leaves.
      _armScanResume();
      return;
    }

    final fromLink = FriendInvite.codeFromText(raw);
    final code = fromLink ?? FriendService.normalize(raw);
    final isCode = code.length == JoinCodeService.codeLength ||
        code.length == FriendService.codeLength;
    if (!isCode) {
      unawaited(widget.vibrationService.lightImpact());
      setState(() => _scanError = 'Not a Bible Read code.');
      return;
    }

    _scanPaused = true;
    unawaited(widget.vibrationService.lightImpact());
    setState(() {
      _scanError = null;
      _controller.text = code;
    });
    await _findCode();
    if (mounted) _armScanResume();
  }

  /// Re-arms the resume timer. Called again on every detection while paused, so
  /// the scanner only resumes after the code has been out of frame for a beat.
  void _armScanResume() {
    _scanIdle?.cancel();
    _scanIdle = Timer(const Duration(seconds: 2), () {
      _scanPaused = false;
    });
  }

  Future<void> _confirmFriend() async {
    final user = widget.auth.currentUser;
    final match = _friendMatch;
    if (user == null || match == null) return;
    unawaited(widget.vibrationService.lightImpact());

    setState(() => _joining = true);
    final result = await redeemFriendCode(
      context,
      friendService: _friendService,
      code: match.code,
      displayName: _displayName(match.name),
    );
    if (!mounted || result == FriendRedemption.added) return;
    setState(() {
      _joining = false;
      final error = switch (result) {
        FriendRedemption.self =>
          "That's your own code. Share it with someone instead.",
        FriendRedemption.alreadyFriends =>
          'You’re already friends with ${_displayName(match.name)}.',
        FriendRedemption.unknown =>
          'That code no longer works. Check it and try again.',
        _ => null,
      };
      if (error != null) {
        _friendMatch = null;
        _error = error;
      }
    });
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
    final colorScheme = Theme.of(context).colorScheme;
    final hasScanner = widget.scanViewBuilder != null;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            SubHeader(
              title: widget.title,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Container(
                decoration: CommonStyles.backgroundDecoration(colorScheme),
                child: SafeArea(
                  child: hasScanner
                      ? Column(
                          children: [
                            _buildScanner(context),
                            Expanded(child: _buildForm(context)),
                          ],
                        )
                      : _buildForm(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanner(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final buildScan = widget.scanViewBuilder!;
    return SizedBox(
      height: 260,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
              color: Colors.black, child: buildScan(context, _onScanned)),
          const IgnorePointer(
            child: QrScanFrame(hint: 'Scan a friend or group code'),
          ),
          if (_scanError != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.gap12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.gap16,
                    vertical: AppSpacing.gap8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppSpacing.rChip),
                  ),
                  child: Text(
                    _scanError!,
                    key: FriendCodeKeys.scanError,
                    style: AppTextStyles.bodySmall(context),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.gap16),
      children: [
        if (widget.scanViewBuilder != null) ...[
          const _OrTypeIt(),
          const SizedBox(height: AppSpacing.gap16),
        ],
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
                      FriendAvatar(
                        name: _friendMatch!.name,
                        photoUrl: _friendMatch!.photoUrl,
                        radius: 22,
                      ),
                      const SizedBox(width: AppSpacing.gap12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayName(_friendMatch!.name),
                              style: AppTextStyles.title(context).copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.gap2),
                            Text(
                              'Friend code',
                              style: AppTextStyles.bodySmall(context).copyWith(
                                color: colorScheme.onSurfaceVariant,
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
                    style: AppTextStyles.bodySmall(context).copyWith(
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
                    style: AppTextStyles.bodySmall(context).copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_match!.isMember) ...[
                    const SizedBox(height: AppSpacing.gap12),
                    Text(
                      "You're already in this group",
                      key: JoinCodeKeys.memberNote,
                      style: AppTextStyles.bodySmall(context).copyWith(
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
                          _match!.group.isPublic ? 'Join group' : 'Ask to join',
                        ),
                      ),
                    ),
                    if (!_match!.group.isPublic) ...[
                      const SizedBox(height: AppSpacing.gap8),
                      Text(
                        'An owner will approve your request before '
                        "you're in.",
                        style: AppTextStyles.bodySmall(context).copyWith(
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
    );
  }
}

/// The "OR TYPE IT" rule that separates the scanner from the code field.
class _OrTypeIt extends StatelessWidget {
  const _OrTypeIt();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gap12),
          child: Text(
            'OR TYPE IT',
            style: AppTextStyles.caption(context).copyWith(
              color: colorScheme.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
