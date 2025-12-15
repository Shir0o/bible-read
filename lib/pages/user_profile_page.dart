import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';

import '../services/error_logger.dart';
import '../services/feedback_service.dart';
import '../services/friend_service.dart';
import '../services/email_preferences_service.dart';
import '../services/google_sign_in_factory.dart';
import '../services/vibration_service.dart';
import '../widgets/achievement_summary.dart';
import '../widgets/animated_action_button.dart';
import '../widgets/animated_page_route.dart';
import '../widgets/common_styles.dart';
import '../widgets/vibration_button.dart';
import 'feedback_page.dart';
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
  final EmailPreferencesService emailPreferencesService;
  final VibrationService vibrationService;
  final FeedbackService feedbackService;

  factory UserProfilePage({
    Key? key,
    GoogleSignInAccount? user,
    GoogleSignIn Function()? googleSignInProvider,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FriendService? friendService,
    EmailPreferencesService? emailPreferencesService,
    VibrationService? vibrationService,
    FeedbackService? feedbackService,
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
      emailPreferencesService:
          emailPreferencesService ?? EmailPreferencesService(firestore: fs),
      vibrationService: vibrationService ?? const VibrationService(),
      feedbackService:
          feedbackService ?? FeedbackService(firestore: fs, auth: authInstance),
    );
  }

  const UserProfilePage._({
    super.key,
    this.user,
    required this.googleSignInProvider,
    required this.auth,
    required this.firestore,
    required this.friendService,
    required this.emailPreferencesService,
    required this.vibrationService,
    required this.feedbackService,
  });

  @override
  State<UserProfilePage> createState() => UserProfilePageState();
}

class UserProfilePageState extends State<UserProfilePage> {
  bool _isSigningIn = false;
  bool _loading = true;
  bool _loadingEmailPrefs = false;
  bool _savingEmailPrefs = false;
  bool _monthlySummaryEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      _loadEmailPreferences();
    });
  }

  Future<void> _loadEmailPreferences() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    setState(() {
      _loadingEmailPrefs = true;
    });
    try {
      final enabled =
          await widget.emailPreferencesService.fetchMonthlySummaryEnabled(uid);
      if (!mounted) return;
      setState(() {
        _monthlySummaryEnabled = enabled;
      });
    } catch (error, stackTrace) {
      await ErrorLogger.log(error, stackTrace);
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingEmailPrefs = false;
      });
    }
  }

  Future<void> _updateMonthlySummaryPreference(bool enabled) async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    setState(() {
      _savingEmailPrefs = true;
      _monthlySummaryEnabled = enabled;
    });
    try {
      await widget.emailPreferencesService
          .updateMonthlySummaryEnabled(uid, enabled);
    } catch (error, stackTrace) {
      await ErrorLogger.log(error, stackTrace);
      if (!mounted) return;
      setState(() {
        _monthlySummaryEnabled = !enabled;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update email preference. Please try again.'),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _savingEmailPrefs = false;
      });
    }
  }

  Future<void> _handleSignIn() async {
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
          Navigator.of(context).pushReplacement(animatedPageRoute(MainPage()));
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

    if (!mounted) return;
    Navigator.of(context).pushReplacement(animatedPageRoute(MainPage()));
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
                                  child: CircleAvatar(
                                    backgroundImage: NetworkImage(photoUrl),
                                    radius: 40,
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
                              const SizedBox(height: 16),
                              AchievementSummary(
                                firestore: widget.firestore,
                                auth: widget.auth,
                              ),
                              const SizedBox(height: 24),
                              _EmailPreferencesCard(
                                loading: _loadingEmailPrefs,
                                enabled: _monthlySummaryEnabled,
                                saving: _savingEmailPrefs,
                                onChanged: _updateMonthlySummaryPreference,
                              ),
                              const SizedBox(height: 24),
                              AnimatedActionButton(
                                onPressed: _handleSignOut,
                                child: const Text('Sign Out'),
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

class _EmailPreferencesCard extends StatelessWidget {
  final bool loading;
  final bool enabled;
  final bool saving;
  final ValueChanged<bool> onChanged;

  const _EmailPreferencesCard({
    required this.loading,
    required this.enabled,
    required this.saving,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Email preferences',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'We send a monthly summary email to highlight your reading '
              'progress. You can opt out at any time.',
            ),
            const SizedBox(height: 8),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else
              SwitchListTile.adaptive(
                value: enabled,
                onChanged: saving ? null : onChanged,
                title: const Text('Receive monthly summary emails'),
                subtitle: Text(
                  saving
                      ? 'Saving preference...'
                      : 'Keep me updated about my monthly progress.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
