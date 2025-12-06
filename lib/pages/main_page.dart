import 'package:bible_read/pages/exercise_challenges_page.dart';
import 'package:bible_read/pages/leaderboard_page.dart';
import 'package:bible_read/pages/user_profile_page.dart';
import 'package:bible_read/pages/friends_page.dart';
import 'package:bible_read/pages/achievements_page.dart';
import 'package:bible_read/pages/groups_page.dart';
import 'package:bible_read/pages/friend_requests_page.dart';
import 'package:bible_read/pages/streak_history_page.dart';
import 'package:bible_read/pages/seasonal_challenges_page.dart';
import 'package:bible_read/pages/friendly_streak_page.dart';
import 'package:bible_read/widgets/navigation_menu_scope.dart';
import 'package:bible_read/widgets/responsive_scaffold.dart';
import 'package:bible_read/widgets/app_menu_sheet.dart';
import '../services/admin_role_service.dart';
import '../services/exercise_tracker_service.dart';
import '../services/friend_service.dart';
import '../services/friendly_streak_service.dart';
import '../services/google_sign_in_factory.dart';
import '../services/group_service.dart';
import '../services/notification_service.dart';
import '../services/vibration_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../services/error_logger.dart';
import 'dart:async';

import 'home_page.dart';
import 'read_log_page.dart';
import 'app_check_error_page.dart';
import 'notification_center_page.dart';
import 'exercise_dashboard_page.dart';
import 'book_tracker_page.dart';

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
  final bool appCheckFailed;

  MainPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    GoogleSignIn Function()? googleSignInProvider,
    FirebaseMessaging? messaging,
    VibrationService? vibrationService,
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
  static const int _readLogIndex = 1;
  static const int _leaderboardIndex = 3;
  static const int _friendsIndex = 4;
  static const int _friendlyStreakIndex = 8;
  static const int _profileIndex = 10;
  static const int _notificationsIndex = 11;
  static const int _exerciseDashboardIndex = 12;
  static const int _bookTrackerIndex = 14;
  static const int _menuDestinationIndex = 2;
  static const List<int> _bottomNavIndices = <int>[
    _homeIndex,
    _readLogIndex,
  ];

  int _selectedIndex = _homeIndex;
  final List<int> _navHistory = [_homeIndex];

  VibrationService get vibrationService => widget.vibrationService;

  late final AdminRoleService _adminRoleService;

  /// Current navigation index, exposed for tests.
  @visibleForTesting
  int get selectedIndex => _selectedIndex;

  /// Allows tests to invoke the tap handler directly.
  @visibleForTesting
  void onItemTapped(int index) => _onItemTapped(index);

  /// Allows tests to trigger menu navigation directly.
  @visibleForTesting
  void navigateFromMenu(int index) => _navigateFromMenu(index);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final FriendService _friendService;
  late final GroupService _groupService;
  late final FriendlyStreakService _friendlyStreakService;
  late final ExerciseTrackerService _exerciseTrackerService;
  final GlobalKey<ReadLogPageState> _readLogKey = GlobalKey<ReadLogPageState>();
  final GlobalKey<LeaderboardPageState> _leaderboardKey =
      GlobalKey<LeaderboardPageState>();
  final GlobalKey<ExerciseDashboardPageState> _exerciseDashboardKey =
      GlobalKey<ExerciseDashboardPageState>();
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
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
        functions: FirebaseFunctions.instance,
        googleSignInProvider: widget.googleSignInProvider,
      ),
      widget.readLogPageBuilder(
        key: _readLogKey,
        firestore: widget.firestore,
        auth: widget.auth,
        onSendLikeNotification: widget.sendLikeNotification ??
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
        onSendCommentNotification: widget.sendCommentNotification ??
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
      SeasonalChallengesPage(
        auth: widget.auth,
      ),
      widget.leaderboardPageBuilder(
        key: _leaderboardKey,
        firestore: widget.firestore,
        auth: widget.auth,
        friendService: _friendService,
      ),
      FriendsPage(friendService: _friendService, auth: widget.auth),
      GroupsPage(groupService: _groupService, auth: widget.auth),
      AchievementsPage(firestore: widget.firestore, auth: widget.auth),
      StreakHistoryPage(),
      FriendlyStreakPage(
        firestore: widget.firestore,
        auth: widget.auth,
        friendlyStreakService: _friendlyStreakService,
      ),
      FriendRequestsPage(friendService: _friendService, auth: widget.auth),
      UserProfilePage(
        googleSignInProvider: widget.googleSignInProvider,
        auth: widget.auth,
        firestore: widget.firestore,
        friendService: _friendService,
      ),
      NotificationCenterPage(
        service: NotificationService(firestore: widget.firestore),
        auth: widget.auth,
        vibrationService: widget.vibrationService,
      ),
      ExerciseDashboardPage(
        key: _exerciseDashboardKey,
        auth: widget.auth,
        trackerService: _exerciseTrackerService,
        vibrationService: widget.vibrationService,
      ),
      ExerciseChallengesPage(
        trackerService: _exerciseTrackerService,
        vibrationService: widget.vibrationService,
      ),
      BookTrackerPage(
        firestore: widget.firestore,
        auth: widget.auth,
      ),
    ];
    assert(
      _pages.length > _friendsIndex,
      '_friendsIndex must remain within _pages bounds.',
    );
    assert(
      _pages[_friendsIndex] is FriendsPage,
      'FriendsPage must stay at _friendsIndex.',
    );
    assert(_pages.length > _friendlyStreakIndex,
        '_friendlyStreakIndex must remain within _pages bounds.');
    assert(
      _pages[_friendlyStreakIndex] is FriendlyStreakPage,
      'FriendlyStreakPage must stay at _friendlyStreakIndex.',
    );
    assert(_pages.length > _notificationsIndex,
        '_notificationsIndex must remain within _pages bounds.');
    assert(
      _pages[_notificationsIndex] is NotificationCenterPage,
      'NotificationCenterPage must stay at _notificationsIndex.',
    );
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
      final prefs = await SharedPreferences.getInstance();
      final cachedToken = prefs.getString('fcmToken');
      if (token != null && token != cachedToken) {
        await prefs.setString('fcmToken', token);
        unawaited(() async {
          try {
            await user.getIdToken(true); // Force-refresh ID token
            await _writeUserMetadata(user, token);
          } catch (e, st) {
            if (kDebugMode) {
              debugPrint('Initial Firestore write failed: $e. Retrying...');
            }
            await ErrorLogger.log(e, st);
            await Future.delayed(const Duration(seconds: 1));
            try {
              await _writeUserMetadata(user, token);
            } catch (e2, st2) {
              if (kDebugMode) {
                debugPrint('Second Firestore write failed: $e2');
              }
              await ErrorLogger.log(e2, st2);
            }
          }
        }());
      } else {
        debugPrint(
          'Skipping Firestore write: token unchanged or null',
        );
      }
    }
  }

  Future<void> _writeUserMetadata(User user, String token) async {
    final userDocRef = widget.firestore.collection('users').doc(user.uid);
    final snap = await userDocRef.get();
    final data = snap.data();
    final emailPrefs = data?['emailPrefs'];
    final hasMonthlySummaryPreference = emailPrefs is Map<String, dynamic> &&
        emailPrefs.containsKey('monthlySummary');

    await userDocRef.set({
      'fcmToken': token,
      'name': user.displayName,
      'email': user.email?.toLowerCase(),
      if (!snap.exists || !hasMonthlySummaryPreference)
        'emailPrefs': {'monthlySummary': true},
    }, SetOptions(merge: true));
  }

  void _onItemTapped(int index) {
    if (widget.appCheckFailed) {
      return;
    }
    final bool signedIn = widget.auth.currentUser != null;
    final int profileIndex = signedIn ? _profileIndex : _homeIndex;
    if (!signedIn && index != profileIndex) {
      return;
    }
    if (_selectedIndex == index) {
      return;
    }
    unawaited(vibrationService.lightImpact());
    _setSelectedIndex(index);
    if (index == _readLogIndex) {
      _readLogKey.currentState?.refresh();
    } else if (index == _leaderboardIndex) {
      _leaderboardKey.currentState?.refresh();
    } else if (index == _exerciseDashboardIndex) {
      unawaited(
        _exerciseDashboardKey.currentState?.refreshSummaries() ??
            Future.value(),
      );
    }
  }

  void _navigateFromMenu(int index) {
    final bool signedIn = widget.auth.currentUser != null;
    final int profileIndex = signedIn ? _profileIndex : _homeIndex;
    if (!signedIn && index != profileIndex) {
      // Block navigation to signed-in pages if not signed in
      return;
    }
    unawaited(vibrationService.lightImpact());
    _setSelectedIndex(index);
    if (index == _readLogIndex) {
      _readLogKey.currentState?.refresh();
    } else if (index == _leaderboardIndex) {
      _leaderboardKey.currentState?.refresh();
    } else if (index == _exerciseDashboardIndex) {
      unawaited(
        _exerciseDashboardKey.currentState?.refreshSummaries() ??
            Future.value(),
      );
    }
  }

  void _setSelectedIndex(int index) {
    setState(() {
      _selectedIndex = index;
      if (_navHistory.last != index) {
        _navHistory.add(index);
      }
    });
  }

  int? _currentDestinationIndex(int destinationCount) {
    final int bottomNavIndex = _bottomNavIndices.indexOf(_selectedIndex);
    if (bottomNavIndex != -1) {
      return bottomNavIndex;
    }
    if (_menuDestinationIndex < destinationCount) {
      return _menuDestinationIndex;
    }
    return null;
  }

  Future<bool> _onWillPop() async {
    if (_navHistory.length > 1) {
      setState(() {
        _navHistory.removeLast();
        _selectedIndex = _navHistory.last;
      });
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.appCheckFailed) {
      return const AppCheckErrorPage();
    }

    final bool signedIn = widget.auth.currentUser != null;
    final List<Widget> pages =
        signedIn ? _pages : <Widget>[_pages[_profileIndex]];
    final bool showBottomNav = signedIn;

    final destinations = showBottomNav
        ? const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.feed), label: 'Feed'),
            NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Menu'),
          ]
        : const <NavigationDestination>[];
    final int navIndex = _currentDestinationIndex(destinations.length) ?? 0;

    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: _onWillPop,
      child: NavigationMenuScope(
        onNavigate: _navigateFromMenu,
        friendlyStreakIndex: _friendlyStreakIndex,
        friendsIndex: _friendsIndex,
        vibrationService: widget.vibrationService,
        adminRoleService: _adminRoleService,
        child: ResponsiveScaffold(
          scaffoldKey: _scaffoldKey,
          selectedIndex: navIndex,
          contentIndex: _selectedIndex,
          onDestinationSelected: _handleNavigationDestinationSelected,
          pages: pages,
          destinations: destinations,
        ),
      ),
    );
  }

  void _handleNavigationDestinationSelected(int destinationIndex) {
    if (destinationIndex >= _bottomNavIndices.length) {
      _showNavigationMenu();
      return;
    }
    final int pageIndex = _bottomNavIndices[destinationIndex];
    _onItemTapped(pageIndex);
  }

  void _showNavigationMenu() {
    unawaited(widget.vibrationService.lightImpact());
    final BuildContext? scopeContext = _scaffoldKey.currentContext;
    final BuildContext fallbackContext = scopeContext ?? context;
    final scope = NavigationMenuScope.maybeOf(fallbackContext);
    if (scope != null) {
      scope.showMenu(fallbackContext);
      return;
    }
    AppMenuSheet.show(
      context: fallbackContext,
      onNavigate: _navigateFromMenu,
      vibrationService: widget.vibrationService,
      adminRoleService: _adminRoleService,
    );
  }
}
