import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/common_styles.dart';

class ReadLogPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  ReadLogPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance;

  @override
  State<ReadLogPage> createState() => _ReadLogPageState();

  static Future<void> writeReadLogEntry(
    User user, {
    FirebaseFirestore? firestore,
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final dateKey =
        '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    await db
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc(user.uid)
        .set({
      'name': (user.displayName ?? '').split(' ').first,
      'email': user.email ?? '',
      'timestamp': Timestamp.now(),
    });
  }
}

class _ReadLogPageState extends State<ReadLogPage> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final currentUser = widget.auth.currentUser;
    if (currentUser == null) {
      setState(() {
        _loading = false;
      });
      return;
    }

    final dateKey =
        '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    final snapshot = await widget.firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .orderBy('timestamp', descending: true)
        .get();

    final logs = await Future.wait(snapshot.docs.map((doc) async {
      final data = doc.data();
      final likeDoc = await doc.reference.collection('likes').doc(currentUser.uid).get();
      return {
        'uid': doc.id,
        'name': (data['name'] ?? doc.id).toString().split(' ').first,
        'read': true,
        'liked': likeDoc.exists,
      };
    }).toList());

    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  Future<void> _toggleLike(String logUid) async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    final dateKey =
        '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    final likeRef = widget.firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc(logUid)
        .collection('likes')
        .doc(user.uid);

    final likeDoc = await likeRef.get();
    if (likeDoc.exists) {
      await likeRef.delete();
    } else {
      await likeRef.set({'timestamp': Timestamp.now()});
    }
    _loadLogs(); // Refresh the UI
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar("Today's Readers"),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: _loading
            ? Container(
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              )
            : widget.auth.currentUser == null
                ? Center(
                    child: Text(
                      'Please sign in to view your read log.',
                      style: TextStyle(
                          fontSize: 18,
                          color: Colors.white70,
                          fontFamily: 'IBMPlexMono'),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(
                        top: 16.0, bottom: 48.0, left: 16, right: 16),
                    child: ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        final isLiked = (log['liked'] as bool? ?? false);
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.check_circle, color: Colors.green),
                            title: Text(
                              '${log['name']} read today!',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            trailing: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: IconButton(
                                icon: Icon(
                                  isLiked ? Icons.favorite : Icons.favorite_border,
                                  color: isLiked ? Colors.red : null,
                                ),
                                onPressed: () => _toggleLike(log['uid']),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}
