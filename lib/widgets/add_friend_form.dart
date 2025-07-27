import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/friend_service.dart';

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
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    final email = _controller.text.trim().toLowerCase();
    if (email.isEmpty) return;
    setState(() {
      _sending = true;
    });
    try {
      await widget.friendService.sendFriendRequestByEmail(
        fromUid: user.uid,
        fromName: user.displayName ?? '',
        toEmail: email,
      );
      if (mounted) {
        _controller.clear();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Request sent')));
        widget.onComplete?.call();
      }
    } catch (e) {
      debugPrint('Failed to send friend request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send request.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
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
        ElevatedButton(
          onPressed: _sending ? null : _sendRequest,
          child: _sending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send'),
        ),
      ],
    );
  }
}
