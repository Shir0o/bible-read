import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/friend_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/friend_requests_button.dart';
import 'add_friend_page.dart';

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
  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    return Scaffold(
      backgroundColor: Colors.black,
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
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AddFriendPage(
                      friendService: widget.friendService,
                      auth: widget.auth,
                    ),
                  ),
                );
              },
              child: const Icon(Icons.add),
            ),
    );
  }
}
