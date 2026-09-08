import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../services/join_code_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/join_code_keys.dart';

/// Redeems a join code: the reader types it, previews which group it lands
/// in, and joins — directly for public groups, as a join request otherwise.
class JoinByCodePage extends StatefulWidget {
  /// Service used to resolve codes and join the group.
  final GroupService groupService;

  /// Auth used for the joining reader.
  final FirebaseAuth auth;

  /// Haptics for interactions.
  final VibrationService vibrationService;

  /// Creates a [JoinByCodePage].
  JoinByCodePage({
    super.key,
    GroupService? groupService,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _findGroup() async {
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

    setState(() {
      _lookingUp = true;
      _match = null;
      _error = null;
    });
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
      appBar: CommonStyles.buildAppBar(context, 'Join with a code'),
      body: Container(
        decoration: CommonStyles.backgroundDecoration(colorScheme),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                key: JoinCodeKeys.codeField,
                controller: _controller,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _findGroup(),
                decoration: const InputDecoration(
                  labelText: 'Join code',
                  hintText: 'e.g. HK2N9P',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: JoinCodeKeys.findButton,
                onPressed: _lookingUp ? null : _findGroup,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _lookingUp
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const Text('Find group'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: JoinCodeKeys.errorText,
                  style: AppTextStyles.bodySmall(context).copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ],
              if (_match != null) ...[
                const SizedBox(height: 24),
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
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _memberCountText(_match!.group.memberCount),
                          style: AppTextStyles.bodySmall(context).copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (_match!.isMember) ...[
                          const SizedBox(height: 12),
                          Text(
                            "You're already in this group",
                            key: JoinCodeKeys.memberNote,
                            style: AppTextStyles.bodySmall(context).copyWith(
                              color: colorScheme.primary,
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 16),
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
                            const SizedBox(height: 8),
                            Text(
                              'An owner will approve your request before '
                              "you're in.",
                              style: AppTextStyles.caption(context).copyWith(
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
    );
  }
}
