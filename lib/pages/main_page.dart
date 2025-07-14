import 'package:bible_read/pages/leaderboard_page.dart';
import 'package:bible_read/pages/user_profile_page.dart';
import 'package:bible_read/widgets/responsive_scaffold.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'home_page.dart';
import 'read_log_page.dart';

class MainPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final GoogleSignIn Function() googleSignInProvider;

  MainPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    GoogleSignIn Function()? googleSignInProvider,
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
    _attemptSilentSignIn().then((_) {
      if (widget.auth.currentUser == null) {
        setState(() {
          _selectedIndex = 0; // Index for UserProfilePage when not logged in
        });
      }
    });
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
    if (widget.auth.currentUser == null && index != 3) {
      // If not logged in, only allow navigation to the profile page (index 3)
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isLoggedIn = widget.auth.currentUser != null;

    final List<Widget> pages = isLoggedIn
        ? <Widget>[
            HomePage(firestore: widget.firestore, auth: widget.auth),
            ReadLogPage(firestore: widget.firestore, auth: widget.auth),
            LeaderboardPage(firestore: widget.firestore, auth: widget.auth),
            UserProfilePage(
              user: _user,
              googleSignInProvider: widget.googleSignInProvider,
              auth: widget.auth,
            ),
          ]
        : <Widget>[
            // Only show UserProfilePage if not logged in
            UserProfilePage(
              user: _user,
              googleSignInProvider: widget.googleSignInProvider,
              auth: widget.auth,
            ),
          ];

    final List<NavigationDestination> destinations = isLoggedIn
        ? const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.feed), label: 'Feed'),
            NavigationDestination(
                icon: Icon(Icons.leaderboard), label: 'Leaderboard'),
            NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
          ]
        : const [
            // Only show Profile destination if not logged in
            NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
          ];

    return ResponsiveScaffold(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _onItemTapped,
      pages: pages,
      destinations: destinations,
    );
  }
}
