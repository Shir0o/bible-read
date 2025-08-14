import 'package:bible_read/pages/leaderboard_page.dart';
import 'package:bible_read/pages/user_profile_page.dart';
import 'package:bible_read/pages/friends_page.dart';
import 'package:bible_read/pages/achievements_page.dart';
import 'package:bible_read/pages/groups_page.dart';
import 'package:bible_read/pages/friend_requests_page.dart';
import 'package:bible_read/pages/streak_history_page.dart';
import 'package:bible_read/widgets/responsive_scaffold.dart';
import 'package:bible_read/widgets/app_drawer.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../services/daily_notification_service.dart';
import '../services/error_logger.dart';

import 'home_page.dart';
import 'read_log_page.dart';
import 'app_check_error_page.dart';

typedef SendLikeNotification =
    Future<void> Function({
      required String ownerUid,
      required String likerName,
    });
typedef SendCommentNotification =
    Future<void> Function({
      required String ownerUid,
      required String commenterName,
    });

class MainPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final GoogleSignIn Function() googleSignInProvider;
  final DailyNotificationService Function() dailyNotificationServiceProvider;
  final SendLikeNotification? sendLikeNotification;
  final SendCommentNotification? sendCommentNotification;
  final FirebaseMessaging messaging;
  final bool appCheckFailed;

  MainPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    GoogleSignIn Function()? googleSignInProvider,
    FirebaseMessaging? messaging,
    DailyNotificationService Function()? dailyNotificationServiceProvider,
    this.sendLikeNotification,
    this.sendCommentNotification,
    this.appCheckFailed = false,
  }) : firestore = firestore ?? FirebaseFirestore.instance,
       auth = auth ?? FirebaseAuth.instance,
       messaging = messaging ?? FirebaseMessaging.instance,
       googleSignInProvider = googleSignInProvider ?? GoogleSignIn.new,
       dailyNotificationServiceProvider =
           dailyNotificationServiceProvider ?? DailyNotificationService.new;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final FriendService _friendService;
  late final GroupService _groupService;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _friendService = FriendService(firestore: widget.firestore);
    _groupService = GroupService(firestore: widget.firestore);
    _pages = [
      HomePage(
        firestore: widget.firestore,
        auth: widget.auth,
        functions: FirebaseFunctions.instance,
      ),
      ReadLogPage(
        firestore: widget.firestore,
        auth: widget.auth,
        onSendLikeNotification:
            widget.sendLikeNotification ??
            ({required String ownerUid, required String likerName}) async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) {
                debugPrint(
                  'Skipping sendLikeNotification: user is not signed in.',
                );
                return;
              }

              await user.getIdToken(true); // Force refresh

              final callable = FirebaseFunctions.instanceFor(
                region: 'us-central1',
              ).httpsCallable('sendLikeNotification');

              await callable.call({
                'ownerUid': ownerUid,
                'likerName': likerName,
              });
            },
        onSendCommentNotification:
            widget.sendCommentNotification ??
            ({required String ownerUid, required String commenterName}) async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) {
                debugPrint(
                  'Skipping sendCommentNotification: user is not signed in.',
                );
                return;
              }

              await user.getIdToken(true);

              final callable = FirebaseFunctions.instanceFor(
                region: 'us-central1',
              ).httpsCallable('sendCommentNotification');

              await callable.call({
                'ownerUid': ownerUid,
                'commenterName': commenterName,
              });
            },
      ),
      LeaderboardPage(
        firestore: widget.firestore,
        auth: widget.auth,
        friendService: _friendService,
      ),
      FriendsPage(friendService: _friendService, auth: widget.auth),
      GroupsPage(groupService: _groupService, auth: widget.auth),
      AchievementsPage(firestore: widget.firestore, auth: widget.auth),
      const StreakHistoryPage(),
      FriendRequestsPage(friendService: _friendService, auth: widget.auth),
      UserProfilePage(
        googleSignInProvider: widget.googleSignInProvider,
        auth: widget.auth,
        firestore: widget.firestore,
        friendService: _friendService,
        dailyNotificationServiceProvider:
            widget.dailyNotificationServiceProvider,
      ),
    ];
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

      setState(() {});
    }
    final user = widget.auth.currentUser;
    if (user != null) {
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
      if (token != null) {
        try {
          await user.getIdToken(true); // Force-refresh ID token
          await widget.firestore.collection('users').doc(user.uid).set({
            'fcmToken': token,
            'name': user.displayName,
            'email': user.email?.toLowerCase(),
          }, SetOptions(merge: true));
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('Initial Firestore write failed: $e. Retrying...');
          }
          ErrorLogger.log(e, st);
          await Future.delayed(const Duration(seconds: 1));
          try {
            await widget.firestore.collection('users').doc(user.uid).set({
              'fcmToken': token,
              'name': user.displayName,
              'email': user.email?.toLowerCase(),
            }, SetOptions(merge: true));
          } catch (e2, st2) {
            if (kDebugMode) {
              debugPrint('Second Firestore write failed: $e2');
            }
            ErrorLogger.log(e2, st2);
          }
        }

        // Schedule daily reminder after preferences load
        await widget.dailyNotificationServiceProvider().scheduleDailyReminder(
          const Time(8, 0),
        );
      } else {
        debugPrint('Skipping Firestore write: user or token is null');
      }
    }
  }

  void _onItemTapped(int index) {
    if (widget.appCheckFailed) {
      return;
    }
    final bool signedIn = widget.auth.currentUser != null;
    final int profileIndex = signedIn ? 8 : 0;
    if (!signedIn && index != profileIndex) {
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  void _navigateFromMenu(int index) {
    final bool signedIn = widget.auth.currentUser != null;
    final int profileIndex = signedIn ? 8 : 0;
    if (!signedIn && index != profileIndex) {
      // Block navigation to signed-in pages if not signed in
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.appCheckFailed) {
      return const AppCheckErrorPage();
    }

    final bool signedIn = widget.auth.currentUser != null;
    final List<Widget> pages = signedIn ? _pages : [_pages.last];

    final int navIndex = signedIn
        ? (_selectedIndex <= 1 ? _selectedIndex : 0)
        : 0;

    return ResponsiveScaffold(
      scaffoldKey: _scaffoldKey,
      drawer: AppDrawer(onNavigate: _navigateFromMenu),
      selectedIndex: navIndex,
      contentIndex: _selectedIndex,
      onDestinationSelected: _onItemTapped,
      pages: pages,
      destinations: [
        if (signedIn) ...const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.feed), label: 'Feed'),
        ] else ...[
          NavigationDestination(
            icon: Hero(tag: 'profile-avatar', child: Icon(Icons.person)),
            label: 'Profile',
          ),
        ],
      ],
    );
  }
}
