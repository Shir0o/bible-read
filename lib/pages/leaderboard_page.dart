import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/friend_service.dart';
import '../services/error_logger.dart';

class LeaderboardPage extends StatelessWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FriendService friendService;

  LeaderboardPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FriendService? friendService,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        friendService = friendService ??
            FriendService(firestore: firestore ?? FirebaseFirestore.instance);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: LeaderboardView(
        firestore: firestore,
        auth: auth,
        friendService: friendService,
      ),
    );
  }
}

class LeaderboardView extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FriendService friendService;

  const LeaderboardView({
    super.key,
    required this.firestore,
    required this.auth,
    required this.friendService,
  });

  @override
  State<LeaderboardView> createState() => _LeaderboardViewState();
}

class _LeaderboardViewState extends State<LeaderboardView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    if (user == null) {
      return const Center(
          child: Text('Please sign in to view the leaderboard.'));
    }

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Friends'),
            Tab(text: 'Public'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _FriendsLeaderboardList(
                firestore: widget.firestore,
                auth: widget.auth,
                friendService: widget.friendService,
              ),
              _GlobalLeaderboardList(
                firestore: widget.firestore,
                auth: widget.auth,
                friendService: widget.friendService,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FriendsLeaderboardList extends StatelessWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FriendService friendService;

  const _FriendsLeaderboardList({
    required this.firestore,
    required this.auth,
    required this.friendService,
  });

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    final stream = friendService
        .friends(user.uid)
        .map((friends) => friends.map((f) => f.uid).toList())
        .asyncMap((friendIds) async {
      final allIds = [user.uid, ...friendIds];
      return _fetchEntries(firestore, allIds);
    });

    return StreamBuilder<List<LeaderboardEntry>>(
      stream: stream,
      builder: (context, snapshot) {
        return _buildList(context, snapshot, user.uid, friendService);
      },
    );
  }
}

class _GlobalLeaderboardList extends StatelessWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FriendService friendService;

  const _GlobalLeaderboardList({
    required this.firestore,
    required this.auth,
    required this.friendService,
  });

  @override
  Widget build(BuildContext context) {
    final stream = firestore
        .collectionGroup('summary')
        .orderBy('streak', descending: true)
        .limit(50)
        .snapshots()
        .asyncMap((snap) async {
      final uids =
          snap.docs.map((d) => d.reference.parent.parent!.id).toList();
      final streaks = {
        for (var d in snap.docs)
          d.reference.parent.parent!.id:
              (d.data() as Map<String, dynamic>)['streak'] as int? ?? 0
      };
      return _fetchEntries(firestore, uids, preloadedStreaks: streaks);
    });

    return StreamBuilder<List<LeaderboardEntry>>(
      stream: stream,
      builder: (context, snapshot) {
        return _buildList(context, snapshot, auth.currentUser?.uid, friendService);
      },
    );
  }
}

class LeaderboardEntry {
  final String uid;
  final String name;
  final int streak;

  LeaderboardEntry({required this.uid, required this.name, required this.streak});
}

Future<List<LeaderboardEntry>> _fetchEntries(
  FirebaseFirestore firestore,
  List<String> uids, {
  Map<String, int>? preloadedStreaks,
}) async {
  if (uids.isEmpty) return [];

  final uniqueUids = uids.toSet().toList();

  final usersData = <String, Map<String, dynamic>>{};
  final userFutures = uniqueUids.map((uid) async {
    try {
      final doc = await firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        usersData[uid] = doc.data()!;
      }
    } catch (_) {
      // ignore
    }
  });
  await Future.wait(userFutures);

  // Fetch Streaks if not preloaded
  final streaks = preloadedStreaks ?? {};
  if (preloadedStreaks == null) {
     final futures = uniqueUids.map((uid) async {
       try {
         final doc = await firestore.collection('users').doc(uid).collection('summary').doc('data').get();
         if (doc.exists) {
           streaks[uid] = (doc.data()?['streak'] as num?)?.toInt() ?? 0;
         } else {
           streaks[uid] = 0;
         }
       } catch (_) {
         streaks[uid] = 0;
       }
     });
     await Future.wait(futures);
  }

  final entries = <LeaderboardEntry>[];
  for (final uid in uniqueUids) {
    final userData = usersData[uid] ?? {};
    final name = userData['displayName'] ?? userData['name'] ?? 'Unknown';
    final streak = streaks[uid] ?? 0;
    entries.add(LeaderboardEntry(uid: uid, name: name, streak: streak));
  }

  entries.sort((a, b) => b.streak.compareTo(a.streak));

  return entries;
}

Widget _buildList(
  BuildContext context,
  AsyncSnapshot<List<LeaderboardEntry>> snapshot,
  String? currentUserId,
  FriendService friendService,
) {
  if (snapshot.hasError) {
    return const Center(child: Text('Error loading leaderboard'));
  }
  if (!snapshot.hasData) {
    return const Center(child: CircularProgressIndicator());
  }

  final entries = snapshot.data!;
  if (entries.isEmpty) {
    return const Center(child: Text('No one is on the leaderboard yet.'));
  }

  return StreamBuilder<QuerySnapshot>(
    stream: currentUserId == null
        ? const Stream.empty()
        : friendService.firestore
            .collection(FriendCollections.users)
            .doc(currentUserId)
            .collection(FriendCollections.sentRequests)
            .snapshots(),
    builder: (context, sentSnap) {
       final sentUids = <String>{};
       if (sentSnap.hasData) {
         for (var d in sentSnap.data!.docs) {
           sentUids.add(d.id);
         }
       }

       return ListView.builder(
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final uid = entry.uid;
          final isMe = uid == currentUserId;
          final name = entry.name;
          final score = entry.streak;
          final isSent = sentUids.contains(uid);

          return ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  isMe ? Theme.of(context).colorScheme.primaryContainer : null,
              child: Text('${index + 1}'),
            ),
            title: Text(name,
                style: isMe ? const TextStyle(fontWeight: FontWeight.bold) : null),
            trailing: Text('$score days'),
            tileColor: isMe ? Theme.of(context).colorScheme.surfaceContainer : null,
            subtitle: (!isMe)
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Tooltip(
                      message: isSent ? 'Friend request sent.' : 'Tap to send a friend request.',
                      child: Icon(
                          isSent ? Icons.check : Icons.person_add,
                          size: 16,
                          color: isSent ? Colors.green : null,
                      ),
                    ),
                  )
                : null,
            onTap: (!isMe && !isSent)
                ? () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Send friend request'),
                        content: Text('Send a friend request to $name?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                               if (currentUserId != null) {
                                 friendService.firestore.collection('users').doc(currentUserId).get().then((snap) {
                                   final myName = snap.data()?['displayName'] ?? snap.data()?['name'] ?? 'Unknown';
                                   friendService.sendFriendRequest(
                                     fromUid: currentUserId,
                                     fromName: myName,
                                     toUid: uid,
                                   ).then((_) {
                                     if (context.mounted) {
                                       Navigator.pop(context);
                                     }
                                   }).catchError((e) {
                                      // ignore
                                   });
                                 });
                               }
                            },
                            child: const Text('Send'),
                          ),
                        ],
                      ),
                    );
                  }
                : null,
          );
        },
      );
    }
  );
}
