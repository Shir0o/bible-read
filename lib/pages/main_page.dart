import 'package:bible_read/pages/community_page.dart';
import 'package:bible_read/pages/journey_page.dart';
import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/widgets/responsive_scaffold.dart';

import 'package:bible_read/widgets/navigation_menu_scope.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'dart:async';

import 'package:bible_read/pages/welcome_page.dart';
import 'package:bible_read/pages/auth_selection_page.dart';
import 'package:bible_read/pages/login_page.dart'; // Added
import 'package:bible_read/widgets/animated_page_route.dart'; // Added
import 'friends_page.dart';
import 'challenges_page.dart';
import 'streak_history_page.dart';
import '../services/admin_role_service.dart';
import '../services/friend_service.dart';

import '../services/google_sign_in_factory.dart';
import '../services/group_service.dart';
import '../services/reading_plan_service.dart';
import '../services/reading_status_service.dart';
import '../services/data_cache_service.dart';
import '../services/user_preferences_service.dart';
import '../services/vibration_service.dart';
import '../services/connectivity_service.dart';
import '../widgets/offline_banner.dart';
import 'app_check_error_page.dart';
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
  final FriendService? friendService;
  final bool appCheckFailed;
  final FirebaseFunctions? functions;

  // Expose onNavigate for testing overrides if needed, though usually not passed
  final bool Function(int)? onNavigate;

  /// Optional handler to mark the first reader for testing.
  final Future<Map<String, dynamic>?> Function({
    required String dateKey,
    required String uid,
  })? markFirstReader;

  MainPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    GoogleSignIn Function()? googleSignInProvider,
    FirebaseMessaging? messaging,
    VibrationService? vibrationService,
    this.readingStatusService,
    this.friendService,
    this.markFirstReader,
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
    this.functions,
    this.onNavigate,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        messaging = messaging ?? FirebaseMessaging.instance,
        googleSignInProvider = googleSignInProvider ?? createGoogleSignIn,
        vibrationService = vibrationService ?? const VibrationService(),
        readLogPageBuilder = readLogPageBuilder ?? ReadLogPage.new;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  static const int _homeIndex = 0;

  int _selectedIndex = _homeIndex;

  // Expose selectedIndex for testing
  @visibleForTesting
  int get selectedIndex => _selectedIndex;

  VibrationService get vibrationService => widget.vibrationService;
  late final AdminRoleService _adminRoleService;
  late final FriendService _friendService;
  late final GroupService _groupService;

  late final ReadingPlanService _readingPlanService;
  late final DataCacheService _cacheService;
  late final ReadingStatusService _readingStatusService;
  late final UserPreferencesService _userPreferencesService;
  late final ConnectivityService _connectivityService;
  late final List<Widget> _pages;
  late final Stream<User?> _authStream;

  final List<int> _navigationHistory = [_homeIndex];
  bool _showAuthSelection = false;

  @override
  void initState() {
    super.initState();
    _authStream = widget.auth.authStateChanges();
    _cacheService = DataCacheService();
    _connectivityService = ConnectivityService();
    // ... rest of init ...
    _readingStatusService = widget.readingStatusService ??
        ReadingStatusService(
          firestore: widget.firestore,
          auth: widget.auth,
          cache: _cacheService,
        );
    _friendService =
        widget.friendService ?? FriendService(firestore: widget.firestore);
    _groupService = GroupService(firestore: widget.firestore);
    _readingPlanService = ReadingPlanService(firestore: widget.firestore);
    _userPreferencesService =
        UserPreferencesService(firestore: widget.firestore);

    _adminRoleService = AdminRoleService(
      firestore: widget.firestore,
      auth: widget.auth,
    );
    unawaited(_adminRoleService.prewarm());
    unawaited(_saveFcmToken());

    _pages = [
      HomePage(
        firestore: widget.firestore,
        auth: widget.auth,
        readingStatusService: _readingStatusService,
        userPreferencesService: _userPreferencesService,
        functions: widget.functions ?? FirebaseFunctions.instance,
        markFirstReader: widget.markFirstReader,
        googleSignInProvider: widget.googleSignInProvider,
        dateProvider: () => DateTime.now(),
      ),
      CommunityPage(
        auth: widget.auth,
        firestore: widget.firestore,
        groupService: _groupService,
        friendService: _friendService,
        readingPlanService: _readingPlanService,
        readingStatusService: _readingStatusService,
        vibrationService: widget.vibrationService,
        readLogBuilder: widget.readLogPageBuilder,
        onSendLikeNotification: widget.sendLikeNotification ??
            ({required String ownerUid, required String likerName}) async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return;
              await user.getIdToken(true);
              final functions = widget.functions ??
                  FirebaseFunctions.instanceFor(region: 'us-central1');
              final callable = functions.httpsCallable('sendLikeNotification');
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
              final functions = widget.functions ??
                  FirebaseFunctions.instanceFor(region: 'us-central1');
              final callable =
                  functions.httpsCallable('sendCommentNotification');
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
        vibrationService: widget.vibrationService,
        dateProvider: () => DateTime.now(),
        cache: _cacheService,
      ),
    ];
  }

  @override
  void dispose() {
    _connectivityService.dispose();
    super.dispose();
  }

  Future<void> _saveFcmToken() async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    try {
      final token = await widget.messaging.getToken();
      if (token != null) {
        await widget.firestore.collection('users').doc(user.uid).set({
          'fcmToken': token,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error saving FCM token: $e');
      }
    }
  }

  // Expose onItemTapped for testing
  @visibleForTesting
  void onItemTapped(int index) {
    _onItemTapped(index);
  }

  void _onItemTapped(int index) {
    if (widget.appCheckFailed) return;
    if (widget.auth.currentUser == null) return;
    if (widget.onNavigate != null && !widget.onNavigate!(index)) return;

    unawaited(vibrationService.lightImpact());
    if (_selectedIndex == index) return;

    setState(() {
      _selectedIndex = index;
      _navigationHistory.add(index);
    });
  }

  // Helper to maintain compatibility if menu expects specific indices,
  // currently menu actions should just be navigation pushes.
  @visibleForTesting
  void navigateFromMenu(int index) {
    _navigateFromMenu(index);
  }

  void _navigateFromMenu(int index) {
    if (widget.appCheckFailed) return;
    if (widget.auth.currentUser == null) return;
    if (widget.onNavigate != null && !widget.onNavigate!(index)) return;

    unawaited(vibrationService.lightImpact());

    if (index >= 0 && index < 3) {
      setState(() {
        _selectedIndex = index;
        _navigationHistory.add(index);
      });
    } else {
      switch (index) {
        case 4: // Friends
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => FriendsPage(
                        auth: widget.auth,
                        friendService: _friendService,
                      )));
          break;
        case 5: // Challenges
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ChallengesPage(
                        auth: widget.auth,
                        firestore: widget.firestore,
                        friendService: _friendService,
                        vibrationService: widget.vibrationService,
                      )));
          break;
        case 7: // History
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => StreakHistoryPage(
                        auth: widget.auth,
                        firestore: widget.firestore,
                      )));
          break;
        case 10: // Sign Out
          unawaited(widget.auth.signOut());
          setState(() {
            _selectedIndex = 0;
            _navigationHistory
              ..clear()
              ..add(0);
          });
          break;
      }
    }
  }

  @override
  void didUpdateWidget(covariant MainPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth) {
      _authStream = widget.auth.authStateChanges();
      _cacheService.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.appCheckFailed) {
      return const AppCheckErrorPage();
    }

    final currentUser = widget.auth.currentUser;

    return StreamBuilder<User?>(
      stream: _authStream,
      initialData: currentUser,
      builder: (context, snapshot) {
        // If we have a user (either from initialData or stream), show the main UI right away.
        // This avoids the stuck-on-loading-screen feeling.
        final user = snapshot.data;

        if (user == null) {
          // If the stream is still waiting and we don't have a currentUser yet, show loader.
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          // Real null user: show Welcome/Auth
          if (_showAuthSelection) {
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                setState(() {
                  _showAuthSelection = false;
                });
              },
              child: AuthSelectionPage(
                auth: widget.auth,
                firestore: widget.firestore,
                googleSignInProvider: widget.googleSignInProvider,
                vibrationService: widget.vibrationService,
                mainPageBuilder: (context) => buildMainPage(context),
              ),
            );
          }
          return WelcomePage(
            onGetStarted: () {
              setState(() {
                _showAuthSelection = true;
              });
            },
            onLogin: () {
              unawaited(widget.vibrationService.lightImpact());
              Navigator.of(context).push(
                animatedPageRoute(
                  LoginPage(
                    auth: widget.auth,
                    firestore: widget.firestore,
                    googleSignInProvider: widget.googleSignInProvider,
                    vibrationService: widget.vibrationService,
                    mainPageBuilder: (context) => buildMainPage(context),
                  ),
                ),
              );
            },
          );
        }

        // We have a user! Show the responsive UI immediately.
        final destinations = const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.people_outlined),
              selectedIcon: Icon(Icons.people),
              label: 'Community'),
          NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Journey'),
        ];

        return PopScope(
          canPop: _navigationHistory.length <= 1,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            setState(() {
              _navigationHistory.removeLast();
              _selectedIndex = _navigationHistory.last;
            });
          },
          child: NavigationMenuScope(
            onNavigate: _navigateFromMenu,
            friendsIndex: 0,
            vibrationService: widget.vibrationService,
            adminRoleService: _adminRoleService,
            child: ResponsiveScaffold(
              selectedIndex:
                  _selectedIndex >= _pages.length ? 0 : _selectedIndex,
              contentIndex: _selectedIndex,
              onDestinationSelected: _onItemTapped,
              pages: _pages,
              destinations: destinations,
              offlineBanner:
                  OfflineBanner(connectivityService: _connectivityService),
            ),
          ),
        );
      },
    );
  }

  Widget buildMainPage(BuildContext context) {
    return MainPage(
      auth: widget.auth,
      firestore: widget.firestore,
      messaging: widget.messaging,
      functions: widget.functions,
      vibrationService: widget.vibrationService,
      googleSignInProvider: widget.googleSignInProvider,
      readingStatusService: widget.readingStatusService,
      markFirstReader: widget.markFirstReader,
      readLogPageBuilder: widget.readLogPageBuilder,
      sendLikeNotification: widget.sendLikeNotification,
      sendCommentNotification: widget.sendCommentNotification,
      appCheckFailed: widget.appCheckFailed,
      onNavigate: widget.onNavigate,
    );
  }
}
