import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/error_logger.dart';
import '../services/friend_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
// import 'friends_page.dart'; // Removed as we are likely using FriendsView now if needed, or keeping it for deeper nav

class LeaderboardView extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FriendService friendService;

  LeaderboardView({
    super.key,
    required this.firestore,
    required this.auth,
    required this.friendService,
  });

  @override
  State<LeaderboardView> createState() => _LeaderboardViewState();
}

class _LeaderboardViewState extends State<LeaderboardView> with SingleTickerProviderStateMixin {
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
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Friends'),
            Tab(text: 'Global'),
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
    if (user == null) return const Center(child: Text('Please sign in'));

    return StreamBuilder<List<String>>(
      stream: friendService.friends(user.uid).map((friends) => friends.map((f) => f.uid).toList()),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Error loading friends'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final friendIds = snapshot.data!;
        if (friendIds.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Add friends to see how they are doing!'),
                const SizedBox(height: 16),
                // Could add a button to go to Friends tab if we had navigation context
              ],
            ),
          );
        }

        final allIds = [user.uid, ...friendIds];

        return StreamBuilder<QuerySnapshot>(
          stream: firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: allIds) // batching? might hit limit if > 30 friends.
              // For a robust implementation, we'd client-side filter or chunk. 
              // Assuming small friend count for now as per minimal implementation.
              .snapshots(),
          builder: (context, snapshot) {
            return _buildList(context, snapshot, user.uid);
          },
        );
      },
    );
  }
}

class _GlobalLeaderboardList extends StatelessWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  const _GlobalLeaderboardList({
    required this.firestore,
    required this.auth,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('users')
          .orderBy('summary.totalReadDays', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        return _buildList(context, snapshot, auth.currentUser?.uid);
      },
    );
  }
}

Widget _buildList(BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot, String? currentUserId) {
  if (snapshot.hasError) {
    return const Center(child: Text('Error loading leaderboard'));
  }
  if (!snapshot.hasData) {
    return const Center(child: CircularProgressIndicator());
  }

  final docs = snapshot.data!.docs;
  // Sort manually if needed (e.g. for friends query which lacks order)
  docs.sort((a, b) {
    final aData = a.data() as Map<String, dynamic>;
    final bData = b.data() as Map<String, dynamic>;
    final aScore = (aData['summary']?['totalReadDays'] ?? 0) as int;
    final bScore = (bData['summary']?['totalReadDays'] ?? 0) as int;
    return bScore.compareTo(aScore);
  });

  return ListView.builder(
    itemCount: docs.length,
    itemBuilder: (context, index) {
      final data = docs[index].data() as Map<String, dynamic>;
      final uid = docs[index].id;
      final isMe = uid == currentUserId;
      final name = data['displayName'] ?? 'Anonymous';
      final score = data['summary']?['totalReadDays'] ?? 0;

      return ListTile(
        leading: CircleAvatar(
          backgroundColor: isMe ? Theme.of(context).colorScheme.primaryContainer : null,
          child: Text('${index + 1}'),
        ),
        title: Text(name, style: isMe ? const TextStyle(fontWeight: FontWeight.bold) : null),
        trailing: Text('$score days'),
        tileColor: isMe ? Theme.of(context).colorScheme.surfaceContainer : null,
      );
    },
  );
}

// Wrapper for backward compatibility
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
        friendService = friendService ?? FriendService(firestore: firestore ?? FirebaseFirestore.instance);

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
