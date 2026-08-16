import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/error_logger.dart';

import '../services/friend_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import 'animated_action_button.dart';
import 'success_animation.dart';

/// Form widget used to send a friend request by email.
class AddFriendForm extends StatefulWidget {
  /// Service used to send the request.
  final FriendService friendService;

  /// Auth instance for the current user.
  final FirebaseAuth auth;

  /// Optional callback when the request completes successfully.
  final VoidCallback? onComplete;

  /// Service used for haptic feedback.
  final VibrationService vibrationService;

  /// Creates an [AddFriendForm].
  const AddFriendForm({
    super.key,
    required this.friendService,
    required this.auth,
    this.onComplete,
    VibrationService? vibrationService,
  }) : vibrationService = vibrationService ?? const VibrationService();

  @override
  State<AddFriendForm> createState() => _AddFriendFormState();
}

class _AddFriendFormState extends State<AddFriendForm> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  Future<void> _sendRequest() async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    final previous = _controller.text;
    final email = previous.trim().toLowerCase();
    if (email.isEmpty) return;

    setState(() => _isLoading = true);
    _controller.clear();

    try {
      await widget.friendService.sendFriendRequestByEmail(
        fromUid: user.uid,
        fromName: user.displayName ?? '',
        toEmail: email,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Request sent')));
      SuccessAnimation.show(context, vibrationService: widget.vibrationService);
      widget.onComplete?.call();
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      if (!mounted) return;
      _controller
        ..text = previous
        ..selection = TextSelection.fromPosition(
          TextPosition(offset: previous.length),
        );
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Failed to send request. Please try again.'),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: AppColors.of(context).borderStrong,
        width: 1,
      ),
    );
    return AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('addFriendEmailField'),
            controller: _controller,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendRequest(),
            style: TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: 16,
              color: colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: "Friend's email",
              prefixIcon: const Icon(Icons.email_outlined, size: 19),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 48,
                minHeight: 48,
              ),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Clear email',
                      onPressed: _controller.clear,
                    )
                  : null,
              filled: true,
              fillColor: colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              hintStyle: TextStyle(
                fontFamily: AppTheme.fontUi,
                fontSize: 16,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          AnimatedActionButton(
            onPressed: _sendRequest,
            isLoading: _isLoading,
            vibrationService: widget.vibrationService,
            child: const Text('Send invitation'),
          ),
        ],
      ),
    );
  }
}
