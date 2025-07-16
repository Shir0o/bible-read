import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/common_styles.dart';

class ReadLogPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final Future<void> Function({
    required String ownerUid,
    required String likerName,
  }) onSendLikeNotification;
  final DateTime Function() dateProvider;

  ReadLogPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    required this.onSendLikeNotification,
    DateTime Function()? dateProvider,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        dateProvider = dateProvider ?? DateTime.now;

  @override
  State<ReadLogPage> createState() => _ReadLogPageState();

  static Future<void> writeReadLogEntry(
    User user, {
    FirebaseFirestore? firestore,
    DateTime Function()? dateProvider,
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final now = (dateProvider ?? DateTime.now)();
    final dateKey = '${now.year}-${now.month}-${now.day}';
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

  Future<void> _sendLikeNotification(
      {required String ownerUid, required String likerName}) async {
    await widget.onSendLikeNotification(
      ownerUid: ownerUid,
      likerName: likerName,
    );
  }

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

    final now = widget.dateProvider();
    final dateKey = '${now.year}-${now.month}-${now.day}';
    final snapshot = await widget.firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .orderBy('timestamp', descending: true)
        .get();

    final logs = await Future.wait(snapshot.docs.map((doc) async {
      final data = doc.data();
      final likesSnapshot = await doc.reference.collection('likes').get();
      final likeDocs = likesSnapshot.docs;
      final liked = likeDocs.any((d) => d.id == currentUser.uid);
      final likeNames = likeDocs
          .map((d) => (d.data()['name'] ?? 'Unknown').toString())
          .toList();
      return {
        'uid': doc.id,
        'name': (data['name'] ?? doc.id).toString().split(' ').first,
        'read': true,
        'liked': liked,
        'likeNames': likeNames,
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
    final now = widget.dateProvider();
    final dateKey = '${now.year}-${now.month}-${now.day}';
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
      final likerName = (user.displayName ?? '').split(' ').first;
      await likeRef.set({
        'timestamp': Timestamp.now(),
        'name': likerName,
      });
      if (logUid != user.uid) {
        await _sendLikeNotification(
          ownerUid: logUid,
          likerName: likerName,
        );
      }
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
                            leading: const Icon(Icons.check_circle,
                                color: Colors.green),
                            title: Text(
                              '${log['name']} read today!',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: () {
                              final likeNames =
                                  (log['likeNames'] as List?) ?? [];
                              if (likeNames.isEmpty) return null;

                              const maxToShow = 3;
                              final displayText = likeNames.length > maxToShow
                                  ? '${likeNames.take(maxToShow).join(", ")} +${likeNames.length - maxToShow} more'
                                  : likeNames.join(", ");

                              return Text('Liked by $displayText');
                            }(),
                            trailing: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4.0),
                              child: IconButton(
                                icon: Icon(
                                  isLiked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
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
