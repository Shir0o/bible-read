import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import '../services/friend_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/notification_button.dart';
import '../services/notification_service.dart';
import '../services/error_logger.dart';
import 'add_friend_page.dart';
import 'friend_requests_page.dart';
import '../widgets/menu_button.dart';

/// Page that lists current friends and allows sending friend requests by email.
class FriendsPage extends StatefulWidget {
  /// Service used to manage friends and requests.
  final FriendService friendService;

  /// Firebase auth instance.
  final FirebaseAuth auth;

  /// Creates a [FriendsPage].
  FriendsPage({super.key, FriendService? friendService, FirebaseAuth? auth})
      : friendService = friendService ?? FriendService(),
        auth = auth ?? FirebaseAuth.instance;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  /// Tracks friends nudged today so the button can be disabled.
  final Set<String> _nudgedToday = <String>{};

  /// Subscription to the nudged today stream.
  StreamSubscription<Set<String>>? _nudgeSub;

  @override
  void initState() {
    super.initState();
    final user = widget.auth.currentUser;
    if (user != null) {
      _nudgeSub = widget.friendService.nudgedToday(user.uid).listen((ids) {
        if (mounted) {
          setState(() {
            _nudgedToday
              ..clear()
              ..addAll(ids);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _nudgeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        'Friends',
        leading: const MenuButton(),
        automaticallyImplyLeading: false,
        actions: [
          if (user != null) ...[
            IconButton(
              icon: const Icon(Icons.person_add),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FriendRequestsPage(
                      friendService: widget.friendService,
                      auth: widget.auth,
                    ),
                  ),
                );
              },
            ),
            NotificationButton(
              service: NotificationService(
                firestore: widget.friendService.firestore,
              ),
              auth: widget.auth,
            ),
          ],
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
                            return const Text('Failed to load data');
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final friends = snapshot.data!;
                          if (friends.isEmpty) {
                            return const Center(child: Text('No friends yet'));
                          }
                          return ListView(
                            children: friends
                                .map(
                                  (f) => ListTile(
                                    title: Text(f.name),
                                    trailing: Builder(
                                      builder: (context) {
                                        final nudged = _nudgedToday.contains(
                                          f.uid,
                                        );
                                        return IconButton(
                                          icon: Icon(
                                            nudged
                                                ? Icons.notifications_off
                                                : Icons.notifications_active,
                                            color: nudged ? Colors.grey : null,
                                          ),
                                          onPressed: nudged
                                              ? null
                                              : () {
                                                  final messenger =
                                                      ScaffoldMessenger.of(
                                                    context,
                                                  );
                                                  setState(() {
                                                    _nudgedToday.add(f.uid);
                                                  });
                                                  messenger.showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Nudge sent',
                                                      ),
                                                    ),
                                                  );
                                                  widget.friendService
                                                      .nudgeFriend(
                                                    currentUid: user.uid,
                                                    friendUid: f.uid,
                                                    currentName:
                                                        user.displayName ??
                                                            'You',
                                                  )
                                                      .catchError((e, st) {
                                                    debugPrint(
                                                      'Failed to send nudge: $e',
                                                    );
                                                    ErrorLogger.log(e, st);
                                                    if (!mounted) {
                                                      return false;
                                                    }
                                                    setState(() {
                                                      _nudgedToday.remove(
                                                        f.uid,
                                                      );
                                                    });
                                                    messenger.showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Failed to send nudge',
                                                        ),
                                                      ),
                                                    );
                                                    return false;
                                                  });
                                                },
                                        );
                                      },
                                    ),
                                  ),
                                )
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
              heroTag: 'friends-fab',
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
