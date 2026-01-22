import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/error_logger.dart';

import '../services/friend_service.dart';
import 'common_styles.dart';

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
  final Map<String, Future<void>> _pending = <String, Future<void>>{};

  void _handleAction(String uid, Future<void> Function() op) {
    setState(() {
      _processing.add(uid);
    });
    final future = op().then((_) {}).catchError((e, st) {
      if (kDebugMode) {
        debugPrint('Failed to process friend request: $e');
      }
      ErrorLogger.log(e, st);
      if (mounted) {
        setState(() {
          _processing.remove(uid);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to update request. Please try again.')),
        );
      }
    }).whenComplete(() {
      _pending.remove(uid);
      if (mounted && _processing.remove(uid)) {
        setState(() {});
      }
    });
    _pending[uid] = future;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FriendRequest>>(
      stream: widget.service.pendingRequests(widget.currentUid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Failed to load data');
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final requests =
            snapshot.data!.where((r) => !_processing.contains(r.uid)).toList();
        if (requests.isEmpty) {
          return const Center(child: Text('No friend requests'));
        }
        return ListView.builder(
          shrinkWrap: true,
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final req = requests[index];
            final uid = req.uid;
            final name = req.name.isEmpty ? 'Unknown' : req.name;
            return CommonStyles.buildTappableCard(
              context: context,
              onTap: () {},
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check),
                      tooltip: 'Accept request',
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
                      tooltip: 'Decline request',
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
              ),
            );
          },
        );
      },
    );
  }
}
