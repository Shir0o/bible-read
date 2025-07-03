import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/common_styles.dart';

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

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
    setState(() {
      _isLoading = true;
    });

    try {
      final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
      final usersData = usersSnapshot.docs.map((doc) => {
        'uid': doc.id,
        'name': doc.data()['name'] ?? 'No Name',
        'email': doc.data()['email'] ?? 'No Email',
      }).toList();

      final leaderboard = <Map<String, dynamic>>[];
      for (final user in usersData) {
        final summaryDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user['uid'])
            .collection('summary')
            .doc('data')
            .get();

        final streak = summaryDoc.exists ? summaryDoc.data()!['streak'] ?? 0 : 0;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading leaderboard: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard', style: CommonStyles.appBarTitleText),
        backgroundColor: Theme.of(context).colorScheme.primary,
        shape: CommonStyles.roundedAppBar,
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _leaderboardData.isEmpty
                ? const Center(child: Text('No one is on the leaderboard yet.'))
                : RefreshIndicator(
                    onRefresh: _loadLeaderboardData,
                    child: ListView.builder(
                      itemCount: _leaderboardData.length,
                      itemBuilder: (context, index) {
                        final user = _leaderboardData[index];
                        final rank = index + 1;
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 4.0),
                          elevation: 2.0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          child: ListTile(
                            leading: Text('$rank',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                            title: Text((user['name'] ?? 'No Name').split(' ').first),
                            trailing: Text('${user['streak']} days',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}
