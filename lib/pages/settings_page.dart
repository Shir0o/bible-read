import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';

import '../models/user_preferences.dart';
import '../services/error_logger.dart';
import '../services/feedback_service.dart';
import '../services/friend_service.dart';
import '../services/notification_preferences_service.dart';
import '../services/user_preferences_service.dart';
import '../services/google_sign_in_factory.dart';
import '../services/vibration_service.dart';
import '../widgets/animated_action_button.dart';
import '../widgets/animated_page_route.dart';
import '../widgets/common_styles.dart';
import '../widgets/vibration_button.dart';
import 'feedback_page.dart';
import 'login_page.dart';
import 'main_page.dart';
import 'notification_settings_page.dart';
import 'signup_page.dart';

class SettingsPage extends StatefulWidget {
  final GoogleSignInAccount? user;
  final GoogleSignIn Function() googleSignInProvider;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FriendService friendService;
  final UserPreferencesService? userPreferencesService;
  final VibrationService vibrationService;
  final FeedbackService feedbackService;
  final Widget Function(BuildContext)? mainPageBuilder;

  factory SettingsPage({
    Key? key,
    GoogleSignInAccount? user,
    GoogleSignIn Function()? googleSignInProvider,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FriendService? friendService,
    UserPreferencesService? userPreferencesService,
    VibrationService? vibrationService,
    FeedbackService? feedbackService,
    Widget Function(BuildContext)? mainPageBuilder,
  }) {
    final authInstance = auth ?? FirebaseAuth.instance;
    final fs = firestore ?? FirebaseFirestore.instance;
    return SettingsPage._(
      key: key,
      user: user,
      googleSignInProvider: googleSignInProvider ?? createGoogleSignIn,
      auth: authInstance,
      firestore: fs,
      friendService: friendService ?? FriendService(firestore: fs),
      userPreferencesService: userPreferencesService,
      vibrationService: vibrationService ?? const VibrationService(),
      feedbackService:
          feedbackService ?? FeedbackService(firestore: fs, auth: authInstance),
      mainPageBuilder: mainPageBuilder,
    );
  }

  const SettingsPage._({
    super.key,
    this.user,
    required this.googleSignInProvider,
    required this.auth,
    required this.firestore,
    required this.friendService,
    this.userPreferencesService,
    required this.vibrationService,
    required this.feedbackService,
    this.mainPageBuilder,
  });

  @override
  State<SettingsPage> createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  bool _isSigningIn = false;
  bool _isSigningOut = false;

  late final UserPreferencesService _prefsService;
  UserPreferences _prefs = const UserPreferences();
  bool _prefsLoading = true;
  StreamSubscription<UserPreferences>? _prefSub;

  @override
  void initState() {
    super.initState();
    _prefsService = widget.userPreferencesService ??
        UserPreferencesService(firestore: widget.firestore);
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        setState(() {
          _prefsLoading = false;
        });
      }
      return;
    }

    _prefSub?.cancel();
    _prefSub = _prefsService.streamPreferences(uid).listen(
      (prefs) {
        if (mounted) {
          setState(() {
            _prefs = prefs;
            _prefsLoading = false;
          });
        }
      },
      onError: (error, stackTrace) {
        ErrorLogger.log(error, stackTrace);
        if (mounted) {
          setState(() {
            _prefsLoading = false;
          });
        }
      },
    );
  }

  Future<void> _updatePreference(bool value) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;

    final oldPrefs = _prefs;
    final newPrefs = _prefs.copyWith(autoMarkPlanRead: value);
    setState(() {
      _prefs = newPrefs;
    });

    try {
      await _prefsService.updatePreferences(uid, newPrefs);
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        setState(() {
          _prefs = oldPrefs;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update preference')),
        );
      }
    }
  }

  @override
  void dispose() {
    _prefSub?.cancel();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (_isSigningIn) return;

    if (mounted) {
      setState(() {
        _isSigningIn = true;
      });
    }
    try {
      final GoogleSignIn googleSignIn = widget.googleSignInProvider();
      final GoogleSignInAccount account = await googleSignIn.authenticate();

      final GoogleSignInAuthentication auth = account.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: auth.idToken,
      );

      await widget.auth.signInWithCredential(credential);

      if (mounted) {
        final page = widget.mainPageBuilder?.call(context) ?? MainPage();
        Navigator.of(context).pushReplacement(animatedPageRoute(page));
      }
    } catch (error, st) {
      if (error is GoogleSignInException &&
          error.code == GoogleSignInExceptionCode.canceled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sign in cancelled')),
          );
        }
      } else {
        if (kDebugMode) {
          debugPrint('Sign in failed: $error');
        }
        ErrorLogger.log(error, st);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Something went wrong')),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
        });
      }
    }
  }

  Future<void> _handleSignOut() async {
    if (_isSigningOut) return;

    if (mounted) {
      setState(() {
        _isSigningOut = true;
      });
    }

    await clearSilentSignInFlag();
    final googleSignIn = widget.googleSignInProvider();
    try {
      await googleSignIn.signOut();
      await googleSignIn.disconnect();
    } catch (error, st) {
      if (kDebugMode) {
        debugPrint('Google sign out failed: $error');
      }
      ErrorLogger.log(error, st);
    }

    try {
      await widget.auth.signOut();
    } catch (error, st) {
      if (kDebugMode) {
        debugPrint('Firebase sign out failed: $error');
      }
      ErrorLogger.log(error, st);
    }

    if (mounted) {
      setState(() {
        _isSigningOut = false;
      });
      final page = widget.mainPageBuilder?.call(context) ?? MainPage();
      Navigator.of(context).pushReplacement(animatedPageRoute(page));
    }
  }

  @override
  Widget build(BuildContext context) {
    final googleUser = widget.user;
    final firebaseUser = widget.auth.currentUser;
    final colorScheme = Theme.of(context).colorScheme;

    Widget body;
    if (firebaseUser == null && googleUser == null) {
      body = Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedActionButton(
              onPressed: _handleSignIn,
              isLoading: _isSigningIn,
              child: const Text('Sign in with Google'),
            ),
            const SizedBox(height: 8),
            VibrationButton(
              vibrationService: widget.vibrationService,
              onPressed: () {
                Navigator.of(context).push(
                  animatedPageRoute(
                    LoginPage(auth: widget.auth),
                  ),
                );
              },
              child: const Text('Email Sign In'),
            ),
            const SizedBox(height: 8),
            VibrationButton(
              vibrationService: widget.vibrationService,
              onPressed: () {
                Navigator.of(context).push(
                  animatedPageRoute(
                    SignupPage(
                      auth: widget.auth,
                      firestore: widget.firestore,
                    ),
                  ),
                );
              },
              child: const Text('Email Sign Up'),
            ),
          ],
        ),
      );
    } else {
      final displayName =
          googleUser?.displayName ?? firebaseUser?.displayName ?? 'No Name';
      final email = googleUser?.email ?? firebaseUser?.email ?? '';
      final photoUrl = googleUser?.photoUrl;

      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile/Account Card
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    if (photoUrl != null && photoUrl.isNotEmpty)
                      Hero(
                        tag: 'profile-avatar',
                        child: CachedNetworkImage(
                          imageUrl: photoUrl,
                          imageBuilder: (context, imageProvider) =>
                              CircleAvatar(
                            backgroundImage: imageProvider,
                            radius: 40,
                          ),
                          placeholder: (context, url) => const CircleAvatar(
                            radius: 40,
                            child: CircularProgressIndicator(),
                          ),
                          errorWidget: (context, url, error) =>
                              const CircleAvatar(
                            radius: 40,
                            child: Icon(Icons.person),
                          ),
                        ),
                      )
                    else
                      const CircleAvatar(
                        radius: 40,
                        child: Icon(Icons.person, size: 40),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      displayName,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    AnimatedActionButton(
                      onPressed: _handleSignOut,
                      isLoading: _isSigningOut,
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // App Settings Section
            Text(
              'App Settings'.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  children: [
                    if (_prefsLoading)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      SwitchListTile(
                        title: const Text('Auto-mark Plan Reading'),
                        subtitle: const Text(
                          'Automatically mark today\'s reading in your personal plan when you mark your daily reading as complete.',
                        ),
                        value: _prefs.autoMarkPlanRead,
                        onChanged: _updatePreference,
                        activeThumbColor: colorScheme.primary,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16.0),
                      ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: const Text('Notification Settings'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        unawaited(widget.vibrationService.lightImpact());
                        Navigator.of(context).push(
                          animatedPageRoute(
                            NotificationSettingsPage(
                              auth: widget.auth,
                              service: NotificationPreferencesService(
                                firestore: widget.firestore,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Support Section
            Text(
              'Support'.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: const Text('Report a Bug'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      unawaited(widget.vibrationService.lightImpact());
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.of(context).push(
                        animatedPageRoute(
                          FeedbackPage(
                            initialTab: FeedbackTab.bug,
                            feedbackService: widget.feedbackService,
                            vibrationService: widget.vibrationService,
                            parentMessenger: messenger,
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.lightbulb_outline),
                    title: const Text('Request a Feature'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      unawaited(widget.vibrationService.lightImpact());
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.of(context).push(
                        animatedPageRoute(
                          FeedbackPage(
                            initialTab: FeedbackTab.feature,
                            feedbackService: widget.feedbackService,
                            vibrationService: widget.vibrationService,
                            parentMessenger: messenger,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        context,
        'Settings',
        automaticallyImplyLeading: false,
      ),
      body: Container(
        decoration: CommonStyles.backgroundDecoration(colorScheme),
        child: Center(
          child: SingleChildScrollView(
            child: body,
          ),
        ),
      ),
    );
  }
}
