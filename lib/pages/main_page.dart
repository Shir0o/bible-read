import 'package:bible_read/pages/leaderboard_page.dart';
import 'package:bible_read/pages/user_profile_page.dart';
import 'package:bible_read/widgets/responsive_scaffold.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'home_page.dart';
import 'read_log_page.dart';

typedef SendLikeNotification = Future<void> Function({
  required String ownerUid,
  required String likerName,
});

class MainPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final GoogleSignIn Function() googleSignInProvider;
  final SendLikeNotification? sendLikeNotification;

  MainPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    GoogleSignIn Function()? googleSignInProvider,
    this.sendLikeNotification,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        googleSignInProvider = googleSignInProvider ?? GoogleSignIn.new;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  GoogleSignInAccount? _user;

  @override
  void initState() {
    super.initState();
    _attemptSilentSignIn();
  }

  Future<void> _attemptSilentSignIn() async {
    final GoogleSignIn googleSignIn = widget.googleSignInProvider();
    final GoogleSignInAccount? account = await googleSignIn.signInSilently();
    if (account != null) {
      final GoogleSignInAuthentication auth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );

      if (widget.auth.currentUser == null) {
        await widget.auth.signInWithCredential(credential);
      }

      setState(() {
        _user = account;
      });

      
    }
  }

  void _onItemTapped(int index) {
    final bool signedIn = widget.auth.currentUser != null;
    final int profileIndex = signedIn ? 3 : 0;
    if (!signedIn && index != profileIndex) {
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool signedIn = widget.auth.currentUser != null;
    final List<Widget> pages = [
      if (signedIn) ...[
        HomePage(firestore: widget.firestore, auth: widget.auth),
        ReadLogPage(
          firestore: widget.firestore,
          auth: widget.auth,
          onSendLikeNotification: ({
            required String ownerUid,
            required String likerName,
          }) async {
            final callable =
                FirebaseFunctions.instance.httpsCallable('sendLikeNotification');
            await callable.call({
              'ownerUid': ownerUid,
              'likerName': likerName,
            });
          },
        ),
        LeaderboardPage(firestore: widget.firestore, auth: widget.auth),
      ],
      UserProfilePage(
        user: _user,
        googleSignInProvider: widget.googleSignInProvider,
        auth: widget.auth,
      ),
    ];

    return ResponsiveScaffold(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _onItemTapped,
      pages: pages,
      destinations: [
        if (signedIn) ...const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.feed), label: 'Feed'),
          NavigationDestination(
              icon: Icon(Icons.leaderboard), label: 'Leaderboard'),
        ],
        const NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
      ],
    );
  }
}
