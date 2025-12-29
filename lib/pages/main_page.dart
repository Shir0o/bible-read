import 'package:bible_read/pages/community_page.dart';
import 'package:bible_read/pages/journey_page.dart';
import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/widgets/responsive_scaffold.dart';
import 'package:bible_read/widgets/app_menu_sheet.dart';
import 'package:bible_read/widgets/navigation_menu_scope.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';

import 'package:bible_read/pages/user_profile_page.dart';
import '../services/admin_role_service.dart';
import '../services/exercise_tracker_service.dart';
import '../services/friend_service.dart';
import '../services/friendly_streak_service.dart';
import '../services/google_sign_in_factory.dart';
import '../services/group_service.dart';
import '../services/reading_status_service.dart';
import '../services/vibration_service.dart';
import 'app_check_error_page.dart';
import 'leaderboard_page.dart';
import 'read_log_page.dart';

typedef SendLikeNotification = Future<void> Function({
  required String ownerUid,
  required String likerName,
});
typedef SendCommentNotification = Future<void> Function({
  required String ownerUid,
  required String commenterName,
});

class MainPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final GoogleSignIn Function() googleSignInProvider;
  final LeaderboardPage Function({
    Key? key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FriendService? friendService,
  }) leaderboardPageBuilder;
  final ReadLogPage Function({
    Key? key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    required SendLikeNotification onSendLikeNotification,
    required SendCommentNotification onSendCommentNotification,
  }) readLogPageBuilder;
  final SendLikeNotification? sendLikeNotification;
  final SendCommentNotification? sendCommentNotification;
  final FirebaseMessaging messaging;
  final VibrationService vibrationService;
  final ReadingStatusService? readingStatusService;
  final bool appCheckFailed;

  MainPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    GoogleSignIn Function()? googleSignInProvider,
    FirebaseMessaging? messaging,
    VibrationService? vibrationService,
    this.readingStatusService,
    LeaderboardPage Function({
      Key? key,
      FirebaseFirestore? firestore,
      FirebaseAuth? auth,
      FriendService? friendService,
    })? leaderboardPageBuilder,
    ReadLogPage Function({
      Key? key,
      FirebaseFirestore? firestore,
      FirebaseAuth? auth,
      required SendLikeNotification onSendLikeNotification,
      required SendCommentNotification onSendCommentNotification,
    })? readLogPageBuilder,
    this.sendLikeNotification,
    this.sendCommentNotification,
    this.appCheckFailed = false,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        messaging = messaging ?? FirebaseMessaging.instance,
        googleSignInProvider = googleSignInProvider ?? createGoogleSignIn,
        vibrationService = vibrationService ?? const VibrationService(),
        leaderboardPageBuilder = leaderboardPageBuilder ?? LeaderboardPage.new,
        readLogPageBuilder = readLogPageBuilder ?? ReadLogPage.new;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  static const int _homeIndex = 0;
  static const int _communityIndex = 1;
  static const int _journeyIndex = 2;

  int _selectedIndex = _homeIndex;

  VibrationService get vibrationService => widget.vibrationService;
  late final AdminRoleService _adminRoleService;
  late final FriendService _friendService;
  late final GroupService _groupService;
  late final FriendlyStreakService _friendlyStreakService;
  late final ExerciseTrackerService _exerciseTrackerService;
  late final ReadingStatusService _readingStatusService;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _readingStatusService = widget.readingStatusService ??
        ReadingStatusService(
            firestore: widget.firestore, auth: widget.auth);
    _friendService = FriendService(firestore: widget.firestore);
    _groupService = GroupService(firestore: widget.firestore);
    _friendlyStreakService = FriendlyStreakService(
      firestore: widget.firestore,
    );
    _exerciseTrackerService = ExerciseTrackerService(
      firestore: widget.firestore,
      auth: widget.auth,
    );
    _adminRoleService = AdminRoleService(
      firestore: widget.firestore,
      auth: widget.auth,
    );
    unawaited(_adminRoleService.prewarm());

    _pages = [
      HomePage(
        firestore: widget.firestore,
        auth: widget.auth,
        readingStatusService: _readingStatusService,
        functions: FirebaseFunctions.instance,
        googleSignInProvider: widget.googleSignInProvider,
      ),
      CommunityPage(
        auth: widget.auth,
        firestore: widget.firestore,
        groupService: _groupService,
        friendService: _friendService,
        readingStatusService: _readingStatusService,
        vibrationService: widget.vibrationService,
        onSendLikeNotification: widget.sendLikeNotification ??
            ({required String ownerUid, required String likerName}) async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return;
              await user.getIdToken(true);
              final callable = FirebaseFunctions.instanceFor(
                region: 'us-central1',
              ).httpsCallable('sendLikeNotification');
              await callable.call({
                'ownerUid': ownerUid,
                'likerName': likerName,
              });
            },
        onSendCommentNotification: widget.sendCommentNotification ??
            ({required String ownerUid, required String commenterName}) async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return;
              await user.getIdToken(true);
              final callable = FirebaseFunctions.instanceFor(
                region: 'us-central1',
              ).httpsCallable('sendCommentNotification');
              await callable.call({
                'ownerUid': ownerUid,
                'commenterName': commenterName,
              });
            },
        dateProvider: () => DateTime.now(),
      ),
      JourneyPage(
        auth: widget.auth,
        firestore: widget.firestore,
      ),
    ];
  }

  void _onItemTapped(int index) {
    if (widget.appCheckFailed) return;
    if (_selectedIndex == index) return;
    unawaited(vibrationService.lightImpact());
    setState(() {
      _selectedIndex = index;
    });
  }

  // Helper to maintain compatibility if menu expects specific indices, 
  // currently menu actions should just be navigation pushes.
  void _navigateFromMenu(int index) {
      // no-op or handle special cases if needed. 
      // The new menu pushes pages directly.
  }

  @override
  Widget build(BuildContext context) {
    if (widget.appCheckFailed) {
      return const AppCheckErrorPage();
    }

    return StreamBuilder<User?>(
      stream: widget.auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
           return const Scaffold(
             body: Center(
               child: CircularProgressIndicator(),
             ),
           );
        }

        final user = snapshot.data;
        if (user == null) {
          return UserProfilePage(
            auth: widget.auth,
            firestore: widget.firestore,
            googleSignInProvider: widget.googleSignInProvider,
            friendService: _friendService,
            vibrationService: widget.vibrationService,
          );
        }

        final destinations = const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.people_outlined), selectedIcon: Icon(Icons.people), label: 'Community'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Journey'),
        ];

        return NavigationMenuScope(
          onNavigate: _navigateFromMenu,
          friendlyStreakIndex: 0, // Legacy indices, not used
          friendsIndex: 0,
          vibrationService: widget.vibrationService,
          adminRoleService: _adminRoleService,
          child: ResponsiveScaffold(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onItemTapped,
            pages: _pages,
            destinations: destinations,
          ),
        );
      },
    );
  }
}
