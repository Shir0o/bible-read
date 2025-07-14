import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/common_styles.dart';

class LeaderboardPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  LeaderboardPage({super.key, FirebaseFirestore? firestore, FirebaseAuth? auth})
      : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance;

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  List<Map<String, dynamic>> _leaderboardData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLeaderboardData();
  }

  Future<void> _loadLeaderboardData() async {
    final currentUser = widget.auth.currentUser;
    if (currentUser == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final usersSnapshot = await widget.firestore.collection('users').get();
      final usersData = usersSnapshot.docs
          .map((doc) => {
                'uid': doc.id,
                'name': doc.data()['name'] ?? 'No Name',
                'email': doc.data()['email'] ?? 'No Email',
              })
          .toList();

      final leaderboard = <Map<String, dynamic>>[];
      for (final user in usersData) {
        final summaryDoc = await widget.firestore
            .collection('users')
            .doc(user['uid'])
            .collection('summary')
            .doc('data')
            .get();

        final streak =
            summaryDoc.exists ? summaryDoc.data()!['streak'] ?? 0 : 0;
        leaderboard.add({
          ...user,
          'streak': streak,
        });
      }

      leaderboard.sort((a, b) => b['streak'].compareTo(a['streak']));

      if (mounted) {
        setState(() {
          _leaderboardData = leaderboard;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error loading leaderboard: $e')),
            );
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard', style: CommonStyles.appBarTitleText),
        backgroundColor: Colors.black,
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: _isLoading
            ? Container(
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              )
            : widget.auth.currentUser == null
                ? Center(
                    child: Text(
                      'User not signed in.',
                      style: TextStyle(fontSize: 18, color: Colors.white70, fontFamily: 'IBMPlexMono'),
                    ),
                  )
                : _leaderboardData.isEmpty
                    ? Container(
                        alignment: Alignment.center,
                        child: const Text('No one is on the leaderboard yet.'))
                    : RefreshIndicator(
                        onRefresh: _loadLeaderboardData,
                        child: Padding(
                          padding: const EdgeInsets.only(
                              top: 16.0, bottom: 48.0, left: 16, right: 16),
                          child: ListView.builder(
                            itemCount: _leaderboardData.length,
                            itemBuilder: (context, index) {
                              final user = _leaderboardData[index];
                              final rank = index + 1;
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4.0),
                                elevation: 2.0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12.0),
                                ),
                                child: ListTile(
                                  leading: Text('$rank',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                  title: Text(
                                      (user['name'] ?? 'No Name').split(' ').first),
                                  trailing: Text('${user['streak']} days',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
      ),
    );
  }
}
