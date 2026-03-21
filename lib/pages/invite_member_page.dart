import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';

/// Page for owners/admins to invite new members to a group.
class InviteMemberPage extends StatefulWidget {
  final Group group;
  final GroupService groupService;
  final FriendService friendService;
  final FirebaseAuth auth;
  final VibrationService vibrationService;

  InviteMemberPage({
    super.key,
    required this.group,
    GroupService? groupService,
    FriendService? friendService,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
  })  : groupService = groupService ?? GroupService(),
        friendService = friendService ?? FriendService(),
        auth = auth ?? FirebaseAuth.instance,
        vibrationService = vibrationService ?? const VibrationService();

  @override
  State<InviteMemberPage> createState() => _InviteMemberPageState();
}

class _InviteMemberPageState extends State<InviteMemberPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searchError = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final lowercaseQuery = query.trim().toLowerCase();
      // Search by email or name (name search is partial but case-sensitive-ish in Firestore)
      // This is a basic implementation. For better search, use multiple queries or Algolia.
      final emailQuery = widget.groupService.firestore
          .collection('users')
          .where('email', isEqualTo: lowercaseQuery)
          .limit(5);

      final nameQuery = widget.groupService.firestore
          .collection('users')
          .where('displayName', isGreaterThanOrEqualTo: query)
          .where('displayName', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(5);

      final snapshots = await Future.wait([emailQuery.get(), nameQuery.get()]);
      final results = <String, Map<String, dynamic>>{};

      for (final snap in snapshots) {
        for (final doc in snap.docs) {
          if (doc.id == widget.auth.currentUser?.uid) continue;
          results[doc.id] = {
            'uid': doc.id,
            'name': doc.data()['displayName'] ?? 'User',
            'email': doc.data()['email'],
            'photoUrl': doc.data()['photoURL'],
          };
        }
      }

      setState(() {
        _searchResults = results.values.toList();
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _searchError = 'Search failed';
      });
    }
  }

  Future<void> _sendInvite(String recipientUid, String recipientName) async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    try {
      unawaited(widget.vibrationService.lightImpact());
      await widget.groupService.sendGroupInvite(
        groupId: widget.group.id,
        groupName: widget.group.name,
        senderUid: user.uid,
        senderName: user.displayName ?? 'Owner',
        recipientUid: recipientUid,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invite sent to $recipientName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send invite')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        context,
        'Invite to ${widget.group.name}',
        leading: BackButton(onPressed: () => Navigator.pop(context)),
      ),
      body: Container(
        decoration:
            CommonStyles.backgroundDecoration(Theme.of(context).colorScheme),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by name or email',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _performSearch('');
                    },
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: _performSearch,
              ),
            ),
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : _searchController.text.isNotEmpty
                      ? _buildSearchResults()
                      : _buildFriendsList(user.uid),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchError != null) {
      return Center(child: Text(_searchError!));
    }
    if (_searchResults.isEmpty) {
      return const Center(child: Text('No users found'));
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final result = _searchResults[index];
        return _buildUserTile(
          uid: result['uid'],
          name: result['name'],
          photoUrl: result['photoUrl'],
        );
      },
    );
  }

  Widget _buildFriendsList(String currentUid) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'MY FRIENDS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder(
            stream: widget.friendService.friends(currentUid),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Failed to load friends'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final friends = snapshot.data!;
              if (friends.isEmpty) {
                return const Center(child: Text('You have no friends yet'));
              }

              return ListView.builder(
                itemCount: friends.length,
                itemBuilder: (context, index) {
                  final friend = friends[index];
                  return _buildUserTile(
                    uid: friend.uid,
                    name: friend.name,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUserTile({
    required String uid,
    required String name,
    String? photoUrl,
  }) {
    return StreamBuilder<DocumentSnapshot>(
      stream: widget.groupService.firestore
          .collection(GroupCollections.groups)
          .doc(widget.group.id)
          .collection(GroupCollections.members)
          .doc(uid)
          .snapshots(),
      builder: (context, memberSnapshot) {
        final isMember = memberSnapshot.data?.exists ?? false;

        return StreamBuilder<DocumentSnapshot>(
          stream: widget.groupService.firestore
              .collection(GroupCollections.groups)
              .doc(widget.group.id)
              .collection(GroupCollections.invites)
              .doc(uid)
              .snapshots(),
          builder: (context, inviteSnapshot) {
            final hasPendingInvite = inviteSnapshot.data?.exists ?? false;

            return ListTile(
              leading: CircleAvatar(
                backgroundImage:
                    photoUrl != null ? NetworkImage(photoUrl) : null,
                child: photoUrl == null ? const Icon(Icons.person) : null,
              ),
              title: Text(name),
              trailing: isMember
                  ? const Text('Already a member')
                  : hasPendingInvite
                      ? const Text('Invite pending')
                      : ElevatedButton(
                          onPressed: () => _sendInvite(uid, name),
                          child: const Text('Invite'),
                        ),
            );
          },
        );
      },
    );
  }
}
