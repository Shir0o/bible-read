import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../services/join_code_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/join_code_keys.dart';
import '../widgets/sub_header.dart';
import '../theme/app_theme.dart';

/// Page to enter a 6-character group join code to preview and join a group.
class JoinByCodePage extends StatefulWidget {
  /// Service used to resolve codes and join the group.
  final GroupService groupService;

  /// Auth used for the joining reader.
  final FirebaseAuth auth;

  /// Haptics for interactions.
  final VibrationService vibrationService;

  /// Header title.
  final String title;

  /// A code to resolve immediately on open (e.g. from an incoming deep link).
  final String? initialCode;

  /// Creates a [JoinByCodePage].
  JoinByCodePage({
    super.key,
    GroupService? groupService,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
    this.initialCode,
    this.title = 'Enter a code',
  })  : groupService = groupService ?? GroupService(),
        auth = auth ?? FirebaseAuth.instance,
        vibrationService = vibrationService ?? const VibrationService();

  @override
  State<JoinByCodePage> createState() => _JoinByCodePageState();
}

class _JoinByCodePageState extends State<JoinByCodePage> {
  final TextEditingController _controller = TextEditingController();
  JoinCodeMatch? _match;
  String? _error;
  bool _lookingUp = false;
  bool _joining = false;

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
        _error = 'Enter the code that was shared with you.';
      });
      return;
    }

    final code =
        JoinCodeService.codeFromText(raw) ?? JoinCodeService.normalize(raw);
    if (code.length != JoinCodeService.codeLength) {
      setState(() {
        _match = null;
        _error = 'Group codes are 6 characters.';
      });
      return;
    }

    setState(() {
      _lookingUp = true;
      _match = null;
      _error = null;
    });

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
          content: Text('You joined ${match.group.name}'),
        ),
      );
      Navigator.of(context).maybePop();
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
                  child: _buildForm(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
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
            hintText: '6-character group code',
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
                        child: const Text('Join group'),
                      ),
                    ),
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
