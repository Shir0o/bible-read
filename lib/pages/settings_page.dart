import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';

import '../models/user_preferences.dart';
import '../theme/app_theme.dart';
import '../services/apple_sign_in_service.dart';
import '../services/error_logger.dart';
import '../services/feedback_service.dart';
import '../services/notification_preferences_service.dart';
import '../services/user_preferences_service.dart';
import '../services/google_sign_in_factory.dart';
import '../services/vibration_service.dart';
import '../widgets/animated_action_button.dart';
import '../widgets/animated_page_route.dart';
import '../widgets/auth/apple_sign_in_button.dart';
import '../widgets/common_styles.dart';
import '../widgets/sub_header.dart';
import '../widgets/vibration_button.dart';
import 'feedback_page.dart';
import 'login_page.dart';
import 'main_page.dart';
import 'notification_settings_page.dart';
import 'signup_page.dart';

class SettingsPage extends StatefulWidget {
  final GoogleSignInAccount? user;
  final GoogleSignIn Function() googleSignInProvider;
  final AppleSignInService appleSignInService;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final UserPreferencesService? userPreferencesService;
  final VibrationService vibrationService;
  final FeedbackService feedbackService;
  final Widget Function(BuildContext)? mainPageBuilder;

  factory SettingsPage({
    Key? key,
    GoogleSignInAccount? user,
    GoogleSignIn Function()? googleSignInProvider,
    AppleSignInService? appleSignInService,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
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
      appleSignInService: appleSignInService ??
          DefaultAppleSignInService(
            auth: authInstance,
            firestore: fs,
          ),
      auth: authInstance,
      firestore: fs,
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
    required this.appleSignInService,
    required this.auth,
    required this.firestore,
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
    // Setting the toggle manually also resolves the one-time prompt, so it
    // won't pop later when finishing a plan reading.
    final newPrefs = _prefs.copyWith(
      autoMarkPlanRead: value,
      syncPromptAnswered: true,
    );
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
      final credential = GoogleAuthProvider.credential(idToken: auth.idToken);

      await widget.auth.signInWithCredential(credential);

      if (mounted) {
        final page = widget.mainPageBuilder?.call(context) ?? MainPage();
        Navigator.of(context).pushReplacement(animatedPageRoute(page));
      }
    } catch (error, st) {
      if (error is GoogleSignInException &&
          error.code == GoogleSignInExceptionCode.canceled) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Sign in cancelled')));
        }
      } else {
        if (kDebugMode) {
          debugPrint('Sign in failed: $error');
        }
        ErrorLogger.log(error, st);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Something went wrong')));
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

  Future<void> _handleAppleSignIn() async {
    if (_isSigningIn) return;

    setState(() {
      _isSigningIn = true;
    });

    try {
      final credential = await widget.appleSignInService.signIn();
      if (credential == null) {
        // Cancelled by user
        return;
      }
      if (mounted) {
        final page = widget.mainPageBuilder?.call(context) ?? MainPage();
        Navigator.of(context).pushReplacement(animatedPageRoute(page));
      }
    } catch (error) {
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

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text(
          'This action is permanent. It will permanently delete all your reading data, '
          'reflections, streaks, and remove you from any reading groups. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _handleDeleteAccount();
    }
  }

  Future<void> _handleDeleteAccount() async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    final uid = user.uid;

    try {
      // 1. Clean up personal Firestore data
      final userDoc = widget.firestore.collection('users').doc(uid);
      try {
        final collections = [
          'summary',
          'settings',
          'plan_progress',
          'reflections',
        ];
        for (final col in collections) {
          final snap = await userDoc.collection(col).get();
          for (final doc in snap.docs) {
            await doc.reference.delete();
          }
        }
        await userDoc.delete();
      } catch (e, st) {
        ErrorLogger.log(e, st);
      }

      // 2. Remove group memberships
      try {
        final memberships = await widget.firestore
            .collectionGroup('members')
            .where('uid', isEqualTo: uid)
            .get();
        for (final mDoc in memberships.docs) {
          await mDoc.reference.delete();
        }
      } catch (e, st) {
        ErrorLogger.log(e, st);
      }

      // 3. Delete Firebase Auth user
      await user.delete();

      // 4. Sign out from Google if connected
      await clearSilentSignInFlag();
      final googleSignIn = widget.googleSignInProvider();
      try {
        await googleSignIn.signOut();
        await googleSignIn.disconnect();
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account deleted successfully')),
        );
        final page = widget.mainPageBuilder?.call(context) ?? MainPage();
        Navigator.of(context).pushReplacement(animatedPageRoute(page));
      }
    } on FirebaseAuthException catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        if (e.code == 'requires-recent-login') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please sign out and sign in again before deleting your account for security.',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? 'Failed to delete account')),
          );
        }
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete account')),
        );
      }
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
            if (widget.appleSignInService.isSupported) ...[
              AppleSignInButton(
                service: widget.appleSignInService,
                onPressed: _handleAppleSignIn,
                height: 48,
                cornerRadius: 12,
              ),
              const SizedBox(height: 8),
            ],
            AnimatedActionButton(
              onPressed: _handleSignIn,
              isLoading: _isSigningIn,
              child: const Text('Sign in with Google'),
            ),
            const SizedBox(height: 8),
            VibrationButton(
              vibrationService: widget.vibrationService,
              onPressed: () {
                Navigator.of(
                  context,
                ).push(animatedPageRoute(LoginPage(auth: widget.auth)));
              },
              child: const Text('Email Sign In'),
            ),
            const SizedBox(height: 8),
            VibrationButton(
              vibrationService: widget.vibrationService,
              onPressed: () {
                Navigator.of(context).push(
                  animatedPageRoute(
                    SignupPage(auth: widget.auth, firestore: widget.firestore),
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
                  if (_prefsLoading)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.hPadding),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    SwitchListTile(
                      title: const Text('Reading counts as showing up'),
                      subtitle: const Text(
                        'When you finish a reading from a plan, it also counts as showing up for the day. Marking "I read today" on its own never moves a plan.',
                      ),
                      value: _prefs.autoMarkPlanRead,
                      onChanged: _updatePreference,
                      activeThumbColor: colorScheme.primary,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.hPadding,
                        vertical: 4,
                      ),
                    ),
                  Divider(
                    height: 1,
                    indent: AppSpacing.hPadding,
                    endIndent: AppSpacing.hPadding,
                    color: colorScheme.outlineVariant,
                  ),
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
            const SizedBox(height: AppSpacing.gap24),

            // Account / Danger zone
            _sectionTitle(context, 'Account'),
            const SizedBox(height: AppSpacing.gap12),
            CommonStyles.buildBorderedCard(
              context: context,
              child: ListTile(
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: colorScheme.error,
                ),
                title: Text(
                  'Delete Account',
                  style: TextStyle(color: colorScheme.error),
                ),
                subtitle: const Text(
                  'Permanently remove your account and all reading data',
                ),
                trailing: const Icon(Icons.chevron_right),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.hPadding,
                ),
                onTap: () {
                  unawaited(widget.vibrationService.lightImpact());
                  _confirmDeleteAccount();
                },
              ),
            ),
            const SizedBox(height: AppSpacing.gap20),
            Text(
              'Bible Read · v1.28.1',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
            ),
            const SizedBox(height: AppSpacing.gap24),
          ],
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: CommonStyles.backgroundDecoration(colorScheme),
        child: SafeArea(
          child: Column(
            children: [
              SubHeader(
                title: 'Settings',
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Center(child: SingleChildScrollView(child: body)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
