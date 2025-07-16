import 'package:flutter/material.dart';

import '../services/friend_service.dart';

/// Widget that lists pending friend requests with accept/decline actions.
class FriendRequestWidget extends StatelessWidget {
  /// Service used to manage friend requests.
  final FriendService service;

  /// Current user id.
  final String currentUid;

  /// Creates the widget.
  const FriendRequestWidget({
    super.key,
    required this.service,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: service.pendingRequests(currentUid),
      builder: (context, snapshot) {
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
            final uid = req['uid'] as String;
            final name = req['name'] ?? 'Unknown';
            return ListTile(
              title: Text(name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: () async {
                      await service.acceptFriendRequest(
                        currentUid: currentUid,
                        fromUid: uid,
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      await service.declineFriendRequest(
                        currentUid: currentUid,
                        fromUid: uid,
                      );
                    },
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
