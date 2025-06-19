import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PublicReadLogPage extends StatefulWidget {
  const PublicReadLogPage({super.key});

  @override
  State<PublicReadLogPage> createState() => _PublicReadLogPageState();

  static Future<void> writeReadLogEntry(User user) async {
    final dateKey = '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    await FirebaseFirestore.instance
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc(user.uid)
        .set({
      'name': user.displayName ?? '',
      'email': user.email ?? '',
      'timestamp': Timestamp.now(),
    });
  }
}

class _PublicReadLogPageState extends State<PublicReadLogPage> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final dateKey = '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    final snapshot = await FirebaseFirestore.instance
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .orderBy('timestamp', descending: true)
        .get();

    final logs = snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'uid': doc.id,
        'name': data['name'] ?? doc.id,
        'email': data['email'] ?? '',
        'read': true,
      };
    }).toList();

    setState(() {
      _logs = logs;
      _loading = false;
    });
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
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: const Icon(Icons.check_circle, color: Colors.green),
                    title: Text('${log['name']} read today!'),
                    subtitle: Text(log['email']),
                  ),
                );
              },
            ),
    );
  }
}