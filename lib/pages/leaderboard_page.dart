import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../services/error_logger.dart';
import '../widgets/common_styles.dart';
import '../widgets/notification_button.dart';
import '../services/notification_service.dart';
import '../widgets/menu_button.dart';
import '../services/friend_service.dart';
import '../models/leaderboard_entry.dart';
import '../theme/app_theme.dart';

class LeaderboardPage extends StatefulWidget {
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
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage>
    with SingleTickerProviderStateMixin {
  List<LeaderboardEntry> _publicData = [];
  List<LeaderboardEntry> _friendsData = [];
  bool _loadingPublic = true;
  bool _loadingFriends = true;

  @override
  void initState() {
    super.initState();
    _loadPublicLeaderboard();
    _loadFriendsLeaderboard();
  }

  Future<void> _loadPublicLeaderboard() async {
    final currentUser = widget.auth.currentUser;
    if (currentUser == null) {
      setState(() {
        _loadingPublic = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _loadingPublic = true;
      });
    }

    try {
      final usersSnapshot = await widget.firestore.collection('users').get();

      final leaderboard = <LeaderboardEntry>[];
      for (final doc in usersSnapshot.docs) {
        final summaryDoc = await widget.firestore
            .collection('users')
            .doc(doc.id)
            .collection('summary')
            .doc('data')
            .get();

        final data = doc.data();
        final streak =
            summaryDoc.exists ? (summaryDoc.data()?['streak'] ?? 0) : 0;
        leaderboard.add(
          LeaderboardEntry(
            uid: doc.id,
            name: data['name'] ?? 'No Name',
            email: data['email'] ?? 'No Email',
            streak: streak,
          ),
        );
      }

      leaderboard.sort((a, b) => b.streak.compareTo(a.streak));

      if (mounted) {
        setState(() {
          _publicData = leaderboard;
        });
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Error loading leaderboard: $e');
      }
      ErrorLogger.log(e, st);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content:
                      Text('Failed to load leaderboard. Please try again.')),
            );
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingPublic = false;
        });
      }
    }
  }

  Future<void> _loadFriendsLeaderboard() async {
    final user = widget.auth.currentUser;
    if (user == null) {
      setState(() {
        _loadingFriends = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _loadingFriends = true;
      });
    }

    try {
      final friendList = await widget.friendService.friends(user.uid).first;
      final entries = <LeaderboardEntry>[];
      for (final friend in friendList) {
        final userDoc =
            await widget.firestore.collection('users').doc(friend.uid).get();
        if (!userDoc.exists) continue;
        final summaryDoc = await widget.firestore
            .collection('users')
            .doc(friend.uid)
            .collection('summary')
            .doc('data')
            .get();

        final data = userDoc.data()!;
        final streak =
            summaryDoc.exists ? (summaryDoc.data()?['streak'] ?? 0) : 0;
        entries.add(
          LeaderboardEntry(
            uid: friend.uid,
            name: data['name'] ?? 'No Name',
            email: data['email'] ?? 'No Email',
            streak: streak,
          ),
        );
      }

      // Include the signed-in user's own data
      final userDoc =
          await widget.firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final summaryDoc = await widget.firestore
            .collection('users')
            .doc(user.uid)
            .collection('summary')
            .doc('data')
            .get();
        final data = userDoc.data()!;
        final streak =
            summaryDoc.exists ? (summaryDoc.data()?['streak'] ?? 0) : 0;
        entries.add(
          LeaderboardEntry(
            uid: user.uid,
            name: data['name'] ?? 'No Name',
            email: data['email'] ?? 'No Email',
            streak: streak,
          ),
        );
      }

      entries.sort((a, b) => b.streak.compareTo(a.streak));

      if (mounted) {
        setState(() {
          _friendsData = entries;
        });
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Error loading friends leaderboard: $e');
      }
      ErrorLogger.log(e, st);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content:
                      Text('Failed to load leaderboard. Please try again.')),
            );
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingFriends = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Leaderboard', style: CommonStyles.appBarTitleText),
          backgroundColor: AppTheme.backgroundColor,
          leading: const MenuButton(),
          automaticallyImplyLeading: false,
          actions: [
            if (user != null)
              NotificationButton(
                service: NotificationService(
                    firestore: widget.friendService.firestore),
                auth: widget.auth,
              ),
          ],
          bottom:
              const TabBar(tabs: [Tab(text: 'Public'), Tab(text: 'Friends')]),
        ),
        body: Container(
          decoration: CommonStyles.backgroundGradient,
          child: TabBarView(
            children: [
              _buildLeaderboard(
                loading: _loadingPublic,
                data: _publicData,
              ),
              _buildLeaderboard(
                loading: _loadingFriends,
                data: _friendsData,
                emptyMessage: 'No friends on the leaderboard yet.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboard({
    required bool loading,
    required List<LeaderboardEntry> data,
    String emptyMessage = 'No one is on the leaderboard yet.',
  }) {
    final user = widget.auth.currentUser;
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (user == null) {
      return Center(
        child: Text(
          'Please sign in to view the leaderboard.',
          style: AppTextStyles.subtitle.copyWith(color: Colors.white70),
        ),
      );
    }
    if (data.isEmpty) {
      return Center(child: Text(emptyMessage));
    }
    return Padding(
      padding:
          const EdgeInsets.only(top: 16.0, bottom: 48.0, left: 16, right: 16),
      child: ListView.builder(
        itemCount: data.length,
        itemBuilder: (context, index) {
          final entry = data[index];
          final rank = index + 1;
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4.0),
            elevation: 2.0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: ListTile(
              leading: Text('$rank',
                  style: AppTextStyles.body
                      .copyWith(fontWeight: FontWeight.bold, fontSize: 16)),
              title: Text(entry.name.split(' ').first),
              trailing: Text('${entry.streak} days',
                  style: AppTextStyles.body
                      .copyWith(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          );
        },
      ),
    );
  }
}
