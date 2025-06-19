import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _readToday = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReadStatus();
  }

  Future<void> _loadReadStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = DateTime.now();
    final dateKey = '${today.year}-${today.month}-${today.day}';

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final userDoc = await userDocRef.get();
    if (!userDoc.exists) {
      await userDocRef.set({
        'name': user.displayName ?? '',
        'email': user.email ?? '',
      });

      final friendsCollection = userDocRef.collection('friends');
      final friendRequestsSentCollection = userDocRef.collection('friendRequestsSent');

      // These can be created later when adding/accepting friends,
      // but you can prepopulate with empty docs or placeholders if needed:
      // Example: initialize placeholder if needed
      await friendsCollection.doc('init').set({'status': 'placeholder', 'timestamp': Timestamp.now()}, SetOptions(merge: true));
      await friendRequestsSentCollection.doc('init').set({'status': 'placeholder', 'timestamp': Timestamp.now()}, SetOptions(merge: true));
    }

    final doc = await userDocRef
        .collection('reading')
        .doc(dateKey)
        .get();

    if (doc.exists && doc.data() != null) {
      setState(() {
        _readToday = doc['read'] ?? false;
      });
    }
    setState(() {
      _loading = false;
    });
  }

  Future<void> _toggleReadStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = DateTime.now();
    final dateKey = '${today.year}-${today.month}-${today.day}';

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final userDoc = await userDocRef.get();
    if (!userDoc.exists) {
      await userDocRef.set({
        'name': user.displayName ?? '',
        'email': user.email ?? '',
      });
    }

    setState(() {
      _readToday = !_readToday;
    });

    await userDocRef
        .collection('reading')
        .doc(dateKey)
        .set({'read': _readToday});

    // Ensure the 'likes' subcollection exists by referencing it.
    // No placeholder documents are created here.
    final likesCollection = userDocRef.collection('reading').doc(dateKey).collection('likes');
    // No write operation needed here unless a like is added.
  }

  Future<void> likeReading() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = DateTime.now();
    final dateKey = '${today.year}-${today.month}-${today.day}';
    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    await userDocRef
        .collection('reading')
        .doc(dateKey)
        .collection('likes')
        .doc(user.uid)
        .set({'timestamp': Timestamp.now()});
  }

  Future<void> unlikeReading() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = DateTime.now();
    final dateKey = '${today.year}-${today.month}-${today.day}';
    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    await userDocRef
        .collection('reading')
        .doc(dateKey)
        .collection('likes')
        .doc(user.uid)
        .delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bible Reading Challenge'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _toggleReadStatus,
              child: Text(_readToday ? 'Mark as Unread' : 'Mark as Read'),
            ),
          ],
        ),
      ),
    );
  }
}