import 'package:bible_read/pages/leaderboard_page.dart';
import 'package:bible_read/pages/user_profile_page.dart';
import 'package:bible_read/widgets/responsive_scaffold.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

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
  final FirebaseMessaging messaging;

  MainPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    GoogleSignIn Function()? googleSignInProvider,
    FirebaseMessaging? messaging,
    this.sendLikeNotification,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        messaging = messaging ?? FirebaseMessaging.instance,
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
      // Request notification permissions for iOS and Android
      if (Platform.isIOS) {
        final settings = await widget.messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        if (settings.authorizationStatus != AuthorizationStatus.authorized) {
          debugPrint('iOS notification permission not granted');
          return;
        }
      }
      if (Platform.isAndroid) {
        if (await Permission.notification.isDenied ||
            await Permission.notification.isPermanentlyDenied) {
          final status = await Permission.notification.request();
          if (!status.isGranted) {
            debugPrint('Android notification permission not granted');
            return;
          }
        }
      }
      final token = await widget.messaging.getToken();
      final user = widget.auth.currentUser;
      if (token != null && user != null) {
        try {
          await user.getIdToken(true); // Force-refresh ID token
          await widget.firestore.collection('users').doc(user.uid).set({
            'fcmToken': token,
            'name': user.displayName,
            'email': user.email,
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('Initial Firestore write failed: $e. Retrying...');
          await Future.delayed(Duration(seconds: 1));
          try {
            await widget.firestore.collection('users').doc(user.uid).set({
              'fcmToken': token,
              'name': user.displayName,
              'email': user.email,
            }, SetOptions(merge: true));
          } catch (e2) {
            debugPrint('Second Firestore write failed: $e2');
          }
        }
      } else {
        debugPrint('Skipping Firestore write: user or token is null');
      }
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
          onSendLikeNotification: widget.sendLikeNotification ??
              ({
                required String ownerUid,
                required String likerName,
              }) async {
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) {
                  debugPrint('Skipping sendLikeNotification: user is not signed in.');
                  return;
                }

                await user.getIdToken(true); // Force refresh

                final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
                    .httpsCallable('sendLikeNotification');

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
