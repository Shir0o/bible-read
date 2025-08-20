import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/error_logger.dart';

import '../services/friend_service.dart';
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

  /// Creates an [AddFriendForm].
  const AddFriendForm({
    super.key,
    required this.friendService,
    required this.auth,
    this.onComplete,
  });

  @override
  State<AddFriendForm> createState() => _AddFriendFormState();
}

class _AddFriendFormState extends State<AddFriendForm> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _sendRequest() {
    final user = widget.auth.currentUser;
    if (user == null) return;
    final previous = _controller.text;
    final email = previous.trim().toLowerCase();
    if (email.isEmpty) return;

    _controller.clear();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Request sent')));

    unawaited(() async {
      try {
        await widget.friendService.sendFriendRequestByEmail(
          fromUid: user.uid,
          fromName: user.displayName ?? '',
          toEmail: email,
        );
        if (!mounted) return;
        SuccessAnimation.show(context);
        widget.onComplete?.call();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('Failed to send friend request: $e');
        }
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
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('addFriendEmailField'),
          controller: _controller,
          decoration: const InputDecoration(labelText: "Friend's Email"),
        ),
        const SizedBox(height: 16),
        AnimatedActionButton(
          onPressed: _sendRequest,
          child: const Text('Send'),
        ),
      ],
    );
  }
}
