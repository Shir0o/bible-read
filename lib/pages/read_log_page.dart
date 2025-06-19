import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ReadLogPage extends StatefulWidget {
  const ReadLogPage({super.key});

  @override
  State<ReadLogPage> createState() => _ReadLogPageState();

  static Future<void> writeReadLogEntry(User user) async {
    final dateKey = '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    await FirebaseFirestore.instance
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
    final currentUser = FirebaseAuth.instance.currentUser;
    final dateKey = '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    final snapshot = await FirebaseFirestore.instance
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .orderBy('timestamp', descending: true)
        .get();

    final logs = await Future.wait(snapshot.docs.map((doc) async {
      final data = doc.data();
      final likeDoc = currentUser != null
          ? await doc.reference.collection('likes').doc(currentUser.uid).get()
          : null;
      return {
        'uid': doc.id,
        'name': (data['name'] ?? doc.id).toString().split(' ').first,
        'read': true,
        'liked': (currentUser != null && likeDoc != null && likeDoc.exists) ? true : false,
      };
    }).toList());

    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  Future<void> _toggleLike(String logUid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final dateKey = '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    final likeRef = FirebaseFirestore.instance
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
      appBar: AppBar(title: const Text("Today's Readers")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final log = _logs[index];
                final isLiked = (log['liked'] as bool? ?? false);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: const Icon(Icons.check_circle, color: Colors.green),
                    title: Text('${log['name']} read today!'),
                    trailing: IconButton(
                      icon: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? Colors.red : null,
                      ),
                      onPressed: () => _toggleLike(log['uid']),
                    ),
                  ),
                );
              },
            ),
    );
  }
}