import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
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

  @override
  void initState() {
    super.initState();
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

  /// Serif section title matching the redesigned design system.
  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w500,
            letterSpacing: -0.2,
          ),
    );
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.hPadding,
          vertical: AppSpacing.gap24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile / account card
            CommonStyles.buildBorderedCard(
              context: context,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.hPadding,
                  vertical: 26,
                ),
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
                    const SizedBox(height: 14),
                    Text(
                      displayName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    AnimatedActionButton(
                      onPressed: _handleSignOut,
                      isLoading: _isSigningOut,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.logout, size: 18),
                          SizedBox(width: 8),
                          Text('Sign Out'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.gap24),

            // App settings
            _sectionTitle(context, 'App settings'),
            const SizedBox(height: AppSpacing.gap12),
            CommonStyles.buildBorderedCard(
              context: context,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text('Notification settings'),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.hPadding,
                    ),
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
            const SizedBox(height: AppSpacing.gap24),

            // Support
            _sectionTitle(context, 'Support'),
            const SizedBox(height: AppSpacing.gap12),
            CommonStyles.buildBorderedCard(
              context: context,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: const Text('Report a bug'),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.hPadding,
                    ),
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
                  Divider(
                    height: 1,
                    indent: AppSpacing.hPadding,
                    endIndent: AppSpacing.hPadding,
                    color: colorScheme.outlineVariant,
                  ),
                  ListTile(
                    leading: const Icon(Icons.lightbulb_outline),
                    title: const Text('Request a feature'),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.hPadding,
                    ),
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
            const SizedBox(height: AppSpacing.gap20),
            Text(
              'Bible Read · v1.0',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
            const SizedBox(height: AppSpacing.gap24),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: CommonStyles.buildAppBar(context, 'Settings'),
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
