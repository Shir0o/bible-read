import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';

import '../services/error_logger.dart';
import '../services/feedback_service.dart';
import '../services/friend_service.dart';

import '../services/google_sign_in_factory.dart';
import '../services/vibration_service.dart';
import '../widgets/animated_action_button.dart';
import '../widgets/animated_page_route.dart';
import '../widgets/common_styles.dart';
import '../widgets/vibration_button.dart';
import 'feedback_page.dart';
import 'general_settings_page.dart';
import 'login_page.dart';
import 'main_page.dart';
import 'notification_settings_page.dart';
import 'signup_page.dart';

class UserProfilePage extends StatefulWidget {
  final GoogleSignInAccount? user;
  final GoogleSignIn Function() googleSignInProvider;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FriendService friendService;

  final VibrationService vibrationService;
  final FeedbackService feedbackService;
  final Widget Function(BuildContext)? mainPageBuilder;

  factory UserProfilePage({
    Key? key,
    GoogleSignInAccount? user,
    GoogleSignIn Function()? googleSignInProvider,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FriendService? friendService,
    VibrationService? vibrationService,
    FeedbackService? feedbackService,
    Widget Function(BuildContext)? mainPageBuilder,
  }) {
    final authInstance = auth ?? FirebaseAuth.instance;
    final fs = firestore ?? FirebaseFirestore.instance;
    return UserProfilePage._(
      key: key,
      user: user,
      googleSignInProvider: googleSignInProvider ?? createGoogleSignIn,
      auth: authInstance,
      firestore: fs,
      friendService: friendService ?? FriendService(firestore: fs),
      vibrationService: vibrationService ?? const VibrationService(),
      feedbackService:
          feedbackService ?? FeedbackService(firestore: fs, auth: authInstance),
      mainPageBuilder: mainPageBuilder,
    );
  }

  const UserProfilePage._({
    super.key,
    this.user,
    required this.googleSignInProvider,
    required this.auth,
    required this.firestore,
    required this.friendService,
    required this.vibrationService,
    required this.feedbackService,
    this.mainPageBuilder,
  });

  @override
  State<UserProfilePage> createState() => UserProfilePageState();
}

class UserProfilePageState extends State<UserProfilePage> {
  bool _isSigningIn = false;
  bool _isSigningOut = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    });
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
      final GoogleSignInAccount? account = await googleSignIn.signIn();
      if (account != null) {
        final GoogleSignInAuthentication auth = await account.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: auth.accessToken,
          idToken: auth.idToken,
        );

        await widget.auth.signInWithCredential(credential);

        if (mounted) {
          final page = widget.mainPageBuilder?.call(context) ?? MainPage();
          Navigator.of(context).pushReplacement(animatedPageRoute(page));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Sign in cancelled')));
        }
      }
    } catch (error, st) {
      if (kDebugMode) {
        debugPrint('Sign in failed: $error');
      }
      ErrorLogger.log(error, st);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Something went wrong')));
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

    final googleSignIn = widget.googleSignInProvider();
    try {
      await googleSignIn.signOut();
      await googleSignIn.disconnect();
    } catch (error, st) {
      if (kDebugMode) {
        debugPrint('Google sign out failed: $error');
      }
      ErrorLogger.log(error, st);
      // Ignore Google sign-out failures.
    }

    try {
      await widget.auth.signOut();
    } catch (error, st) {
      if (kDebugMode) {
        debugPrint('Firebase sign out failed: $error');
      }
      ErrorLogger.log(error, st);
      // Ignore Firebase sign-out failures.
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
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        context,
        'Profile',
        automaticallyImplyLeading: false,
      ),
      body: Container(
        decoration:
            CommonStyles.backgroundDecoration(Theme.of(context).colorScheme),
        child: Center(
          child: SingleChildScrollView(
            child: () {
              return _loading
                  ? const CircularProgressIndicator()
                  : ((firebaseUser == null && googleUser == null)
                      ? Column(
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
                        )
                      : () {
                          final displayName = googleUser?.displayName ??
                              firebaseUser?.displayName ??
                              'No Name';
                          final email =
                              googleUser?.email ?? firebaseUser?.email ?? '';
                          final photoUrl = googleUser?.photoUrl;
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
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
                                    placeholder: (context, url) =>
                                        const CircleAvatar(
                                      radius: 40,
                                      child: CircularProgressIndicator(),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        const CircleAvatar(
                                      radius: 40,
                                      child: Icon(Icons.person),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 16),
                              Text(
                                displayName,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                email,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 24),
                              AnimatedActionButton(
                                onPressed: _handleSignOut,
                                isLoading: _isSigningOut,
                                child: const Text('Sign Out'),
                              ),
                              const SizedBox(height: 8),
                              VibrationButton(
                                vibrationService: widget.vibrationService,
                                onPressed: () {
                                  Navigator.of(context).push(
                                    animatedPageRoute(
                                      GeneralSettingsPage(
                                        auth: widget.auth,
                                        firestore: widget.firestore,
                                      ),
                                    ),
                                  );
                                },
                                child: const Text('General Settings'),
                              ),
                              const SizedBox(height: 8),
                              VibrationButton(
                                vibrationService: widget.vibrationService,
                                onPressed: () {
                                  Navigator.of(context).push(
                                    animatedPageRoute(
                                      NotificationSettingsPage(),
                                    ),
                                  );
                                },
                                child: const Text('Notification Settings'),
                              ),
                              const SizedBox(height: 8),
                              VibrationButton(
                                vibrationService: widget.vibrationService,
                                onPressed: () {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  Navigator.of(context).push(
                                    animatedPageRoute(
                                      FeedbackPage(
                                        initialTab: FeedbackTab.bug,
                                        feedbackService: widget.feedbackService,
                                        vibrationService:
                                            widget.vibrationService,
                                        parentMessenger: messenger,
                                      ),
                                    ),
                                  );
                                },
                                child: const Text('Report a Bug'),
                              ),
                              const SizedBox(height: 8),
                              VibrationButton(
                                vibrationService: widget.vibrationService,
                                onPressed: () {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  Navigator.of(context).push(
                                    animatedPageRoute(
                                      FeedbackPage(
                                        initialTab: FeedbackTab.feature,
                                        feedbackService: widget.feedbackService,
                                        vibrationService:
                                            widget.vibrationService,
                                        parentMessenger: messenger,
                                      ),
                                    ),
                                  );
                                },
                                child: const Text('Request a Feature'),
                              ),
                            ],
                          );
                        }());
            }(),
          ),
        ),
      ),
    );
  }
}
