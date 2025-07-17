import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/friend_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/friend_requests_button.dart';

/// Page that lists current friends and allows sending friend requests by email.
class FriendsPage extends StatefulWidget {
  /// Service used to manage friends and requests.
  final FriendService friendService;

  /// Firebase auth instance.
  final FirebaseAuth auth;

  /// Creates a [FriendsPage].
  FriendsPage({
    super.key,
    FriendService? friendService,
    FirebaseAuth? auth,
  })  : friendService = friendService ?? FriendService(),
        auth = auth ?? FirebaseAuth.instance;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final TextEditingController _emailController = TextEditingController();
  bool _sending = false;

  Future<void> _showAddFriendDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Friend'),
          content: TextField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: "Friend's Email",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _sending
                  ? null
                  : () async {
                      Navigator.of(context).pop();
                      await _sendRequest();
                    },
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
      },
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    final email = _emailController.text.trim();
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
        _emailController.clear();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Request sent')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send request: $e')),
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
    final user = widget.auth.currentUser;
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        'Friends',
        actions: [
          if (user != null)
            FriendRequestsButton(
              friendService: widget.friendService,
              auth: widget.auth,
            ),
        ],
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: user == null
            ? const Center(child: Text('Please sign in'))
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    Expanded(
                      child: StreamBuilder<List<Friend>>(
                        stream: widget.friendService.friends(user.uid),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Text('Error: ${snapshot.error}');
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          final friends = snapshot.data!;
                          if (friends.isEmpty) {
                            return const Text('No friends yet');
                          }
                          return ListView(
                            children: friends
                                .map((f) => ListTile(title: Text(f.name)))
                                .toList(),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
      ),
      floatingActionButton: user == null
          ? null
          : FloatingActionButton(
              onPressed: _showAddFriendDialog,
              child: const Icon(Icons.add),
            ),
    );
  }
}
