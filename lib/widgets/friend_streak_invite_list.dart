import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/friend_streak_link.dart';
import '../services/error_logger.dart';
import '../services/friend_service.dart';
import 'common_styles.dart';

/// Widget that renders pending streak invites with accept and decline controls.
class FriendStreakInviteList extends StatefulWidget {
  /// Service that manages streak invites.
  final FriendService service;

  /// UID of the signed-in user.
  final String currentUid;

  /// Creates the widget.
  const FriendStreakInviteList({
    super.key,
    required this.service,
    required this.currentUid,
  });

  @override
  State<FriendStreakInviteList> createState() => _FriendStreakInviteListState();
}

class _FriendStreakInviteListState extends State<FriendStreakInviteList> {
  final Set<String> _processing = <String>{};

  void _handleAction(String partnerUid, Future<void> Function() op) {
    setState(() => _processing.add(partnerUid));
    op().catchError((error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Failed to update streak invite: $error');
      }
      ErrorLogger.log(error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update invite. Please try again.'),
          ),
        );
      }
    }).whenComplete(() {
      if (mounted) {
        setState(() => _processing.remove(partnerUid));
      } else {
        _processing.remove(partnerUid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FriendStreakLink>>(
      stream: widget.service
          .pendingStreakInvites(widget.currentUid, actionableOnly: true),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Failed to load streak invites');
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final invites = snapshot.data!;
        if (invites.isEmpty) {
          return const Center(child: Text('No streak invites'));
        }
        return ListView.builder(
          shrinkWrap: true,
          itemCount: invites.length,
          itemBuilder: (context, index) {
            final invite = invites[index];
            final partnerUid = invite.partnerUid;
            final name = invite.partnerName?.isNotEmpty == true
                ? invite.partnerName!
                : 'Friend';
            final busy = _processing.contains(partnerUid);
            return CommonStyles.buildTappableCard(
              onTap: () {},
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(name),
                subtitle: const Text('Wants to start a streak with you'),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => _handleAction(
                                partnerUid,
                                () => widget.service.respondToStreakInvite(
                                  currentUid: widget.currentUid,
                                  partnerUid: partnerUid,
                                  accept: false,
                                ),
                              ),
                      child: const Text('Decline'),
                    ),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => _handleAction(
                                partnerUid,
                                () => widget.service.respondToStreakInvite(
                                  currentUid: widget.currentUid,
                                  partnerUid: partnerUid,
                                  accept: true,
                                ),
                              ),
                      child: const Text('Accept'),
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
