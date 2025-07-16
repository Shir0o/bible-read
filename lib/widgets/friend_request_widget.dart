import 'package:flutter/material.dart';

import '../services/friend_service.dart';

/// Widget that lists pending friend requests with accept/decline actions.
class FriendRequestWidget extends StatefulWidget {
  /// Service used to manage friend requests.
  final FriendService service;

  /// Current user id.
  final String currentUid;

  /// Current user's display name used when accepting requests.
  final String currentName;

  /// Creates the widget.
  const FriendRequestWidget({
    super.key,
    required this.service,
    required this.currentUid,
    required this.currentName,
  });

  @override
  State<FriendRequestWidget> createState() => _FriendRequestWidgetState();
}

class _FriendRequestWidgetState extends State<FriendRequestWidget> {
  final Set<String> _processing = <String>{};

  Future<void> _handleAction(String uid, Future<void> Function() op) async {
    setState(() {
      _processing.add(uid);
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await op();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _processing.remove(uid);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FriendRequest>>(
      stream: widget.service.pendingRequests(widget.currentUid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final requests = snapshot.data!;
        if (requests.isEmpty) {
          return const Text('No friend requests');
        }
        return ListView.builder(
          shrinkWrap: true,
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final req = requests[index];
            final uid = req.uid;
            final name = req.name.isEmpty ? 'Unknown' : req.name;
            final loading = _processing.contains(uid);
            return ListTile(
              title: Text(name),
              trailing: loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check),
                          onPressed: () => _handleAction(
                            uid,
                            () => widget.service.acceptFriendRequest(
                              currentUid: widget.currentUid,
                              currentName: widget.currentName,
                              fromUid: uid,
                              fromName: name,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => _handleAction(
                            uid,
                            () => widget.service.declineFriendRequest(
                              currentUid: widget.currentUid,
                              fromUid: uid,
                            ),
                          ),
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }
}
