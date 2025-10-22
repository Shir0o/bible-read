import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../services/error_logger.dart';
import '../widgets/common_styles.dart';
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
  }) : firestore = firestore ?? FirebaseFirestore.instance,
       auth = auth ?? FirebaseAuth.instance,
       friendService =
           friendService ??
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
  Set<String> _friendIds = {};
  Set<String> _sentRequestIds = {};
  Set<String> _receivedRequestIds = {};

  @override
  void initState() {
    super.initState();
    _loadPublicLeaderboard();
    _loadFriendsLeaderboard();
    _loadFriendRequestStatus();
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
        final streak = summaryDoc.exists
            ? (summaryDoc.data()?['streak'] ?? 0)
            : 0;
        leaderboard.add(
          LeaderboardEntry(
            uid: doc.id,
            name: data['name'] as String? ?? '',
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
                content: Text('Failed to load leaderboard. Please try again.'),
              ),
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
        _friendIds = {};
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
      final friendIds = <String>{};
      final entries = <LeaderboardEntry>[];
      for (final friend in friendList) {
        friendIds.add(friend.uid);
        final userDoc = await widget.firestore
            .collection('users')
            .doc(friend.uid)
            .get();
        if (!userDoc.exists) continue;
        final summaryDoc = await widget.firestore
            .collection('users')
            .doc(friend.uid)
            .collection('summary')
            .doc('data')
            .get();

        final data = userDoc.data()!;
        final streak = summaryDoc.exists
            ? (summaryDoc.data()?['streak'] ?? 0)
            : 0;
        entries.add(
          LeaderboardEntry(
            uid: friend.uid,
            name: data['name'] as String? ?? '',
            email: data['email'] ?? 'No Email',
            streak: streak,
          ),
        );
      }

      // Include the signed-in user's own data
      final userDoc = await widget.firestore
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists) {
        final summaryDoc = await widget.firestore
            .collection('users')
            .doc(user.uid)
            .collection('summary')
            .doc('data')
            .get();
        final data = userDoc.data()!;
        final streak = summaryDoc.exists
            ? (summaryDoc.data()?['streak'] ?? 0)
            : 0;
        entries.add(
          LeaderboardEntry(
            uid: user.uid,
            name: data['name'] as String? ?? '',
            email: data['email'] ?? 'No Email',
            streak: streak,
          ),
        );
      }

      entries.sort((a, b) => b.streak.compareTo(a.streak));

      if (mounted) {
        setState(() {
          _friendsData = entries;
          _friendIds = friendIds;
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
                content: Text('Failed to load leaderboard. Please try again.'),
              ),
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

  Future<void> _loadFriendRequestStatus() async {
    final user = widget.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _sentRequestIds = {};
          _receivedRequestIds = {};
        });
      }
      return;
    }

    try {
      final sentSnapshot = await widget.firestore
          .collection(FriendCollections.users)
          .doc(user.uid)
          .collection(FriendCollections.sentRequests)
          .get();
      final receivedSnapshot = await widget.firestore
          .collection(FriendCollections.users)
          .doc(user.uid)
          .collection(FriendCollections.receivedRequests)
          .get();

      final sentIds = <String>{
        for (final doc in sentSnapshot.docs)
          if (doc.id != 'init') doc.id,
      };
      final receivedIds = <String>{
        for (final doc in receivedSnapshot.docs)
          if (doc.id != 'init') doc.id,
      };

      if (mounted) {
        setState(() {
          _sentRequestIds = sentIds;
          _receivedRequestIds = receivedIds;
        });
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Error loading friend request status: $e');
      }
      ErrorLogger.log(e, st);
    }
  }

  /// Reloads leaderboard data.
  Future<void> refresh() async {
    await Future.wait([
      _loadPublicLeaderboard(),
      _loadFriendsLeaderboard(),
      _loadFriendRequestStatus(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Leaderboard', style: CommonStyles.appBarTitleText),
          backgroundColor: AppTheme.backgroundColor,
          automaticallyImplyLeading: false,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Public'),
              Tab(text: 'Friends'),
            ],
          ),
        ),
        body: Container(
          decoration: CommonStyles.backgroundGradient,
          child: TabBarView(
            children: [
              _buildLeaderboard(
                loading: _loadingPublic,
                data: _publicData,
                showFriendActions: true,
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
    bool showFriendActions = false,
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
      padding: const EdgeInsets.only(
        top: 16.0,
        bottom: 48.0,
        left: 16,
        right: 16,
      ),
      child: ListView.builder(
        itemCount: data.length,
        itemBuilder: (context, index) {
          final entry = data[index];
          final rank = index + 1;
          final isCurrentUser = entry.uid == user.uid;
          final displayName = _entryDisplayName(entry);
          final colorScheme = Theme.of(context).colorScheme;
          Widget? friendStatusIcon;
          final canSendRequest = showFriendActions &&
              !isCurrentUser &&
              !_friendIds.contains(entry.uid) &&
              !_sentRequestIds.contains(entry.uid) &&
              !_receivedRequestIds.contains(entry.uid);

          if (showFriendActions && !isCurrentUser) {
            if (_friendIds.contains(entry.uid)) {
              friendStatusIcon = Tooltip(
                message: "You're already friends.",
                child: Semantics(
                  label: "You're already friends.",
                  child: Icon(
                    Icons.check_circle,
                    color: colorScheme.primary,
                    size: 18,
                  ),
                ),
              );
            } else if (_sentRequestIds.contains(entry.uid)) {
              friendStatusIcon = Tooltip(
                message: 'Friend request sent.',
                child: Semantics(
                  label: 'Friend request sent.',
                  child: Icon(
                    Icons.schedule_send,
                    color: colorScheme.secondary,
                    size: 18,
                  ),
                ),
              );
            } else if (_receivedRequestIds.contains(entry.uid)) {
              friendStatusIcon = Tooltip(
                message: 'This user sent you a friend request.',
                child: Semantics(
                  label: 'This user sent you a friend request.',
                  child: Icon(
                    Icons.mark_email_unread,
                    color: colorScheme.tertiary,
                    size: 18,
                  ),
                ),
              );
            } else {
              friendStatusIcon = Tooltip(
                message: 'Tap to send a friend request.',
                child: Semantics(
                  button: true,
                  label: 'Tap to send a friend request.',
                  child: Icon(
                    Icons.person_add_alt_1,
                    color: colorScheme.primary,
                    size: 18,
                  ),
                ),
              );
            }
          }
          return CommonStyles.buildTappableCard(
            onTap: canSendRequest ? () => _handleEntryTap(entry) : null,
            margin: const EdgeInsets.symmetric(vertical: 4.0),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Text(
                '$rank',
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              title: Text(displayName),
              subtitle: friendStatusIcon == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: friendStatusIcon,
                      ),
                    ),
              trailing: Text(
                '${entry.streak} days',
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleEntryTap(LeaderboardEntry entry) async {
    final user = widget.auth.currentUser;
    if (user == null) {
      return;
    }
    if (entry.uid == user.uid ||
        _friendIds.contains(entry.uid) ||
        _sentRequestIds.contains(entry.uid) ||
        _receivedRequestIds.contains(entry.uid)) {
      return;
    }
    final confirmed = await _confirmSendFriendRequest(entry);
    if (confirmed != true) {
      return;
    }
    await _sendFriendRequest(entry);
  }

  Future<bool?> _confirmSendFriendRequest(LeaderboardEntry entry) {
    final context = this.context;
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Send friend request'),
          content: Text(
            'Send a friend request to ${_entryDisplayName(entry)}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendFriendRequest(LeaderboardEntry entry) async {
    final user = widget.auth.currentUser;
    if (user == null) {
      return;
    }
    try {
      final userDoc = await widget.firestore
          .collection('users')
          .doc(user.uid)
          .get();
      final fromName = userDoc.data()?['name'] as String? ?? '';
      await widget.friendService.sendFriendRequest(
        fromUid: user.uid,
        fromName: fromName,
        toUid: entry.uid,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _sentRequestIds = {..._sentRequestIds, entry.uid};
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Friend request sent.')));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to send friend request: $e');
      }
      ErrorLogger.log(e, st);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send friend request. Please try again.'),
        ),
      );
    }
  }

  String _entryDisplayName(LeaderboardEntry entry) {
    if (entry.name.isEmpty || entry.name == 'No Name') {
      return 'Unknown';
    }
    return entry.name.split(' ').first;
  }
}

typedef LeaderboardPageState = _LeaderboardPageState;
