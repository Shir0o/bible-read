import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../widgets/common_styles.dart';
import '../widgets/notification_button.dart';
import '../services/notification_service.dart';
import '../services/friend_service.dart';
import '../widgets/achievement_summary.dart';
import 'notification_settings_page.dart';
import 'main_page.dart';
import 'login_page.dart';
import 'signup_page.dart';

class UserProfilePage extends StatefulWidget {
  final GoogleSignInAccount? user;
  final GoogleSignIn Function() googleSignInProvider;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FriendService friendService;

  factory UserProfilePage({
    Key? key,
    GoogleSignInAccount? user,
    GoogleSignIn Function()? googleSignInProvider,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FriendService? friendService,
  }) {
    final fs = firestore ?? FirebaseFirestore.instance;
    return UserProfilePage._(
      key: key,
      user: user,
      googleSignInProvider: googleSignInProvider ?? GoogleSignIn.new,
      auth: auth ?? FirebaseAuth.instance,
      firestore: fs,
      friendService: friendService ?? FriendService(firestore: fs),
    );
  }

  const UserProfilePage._({
    super.key,
    this.user,
    required this.googleSignInProvider,
    required this.auth,
    required this.firestore,
    required this.friendService,
  });

  @override
  State<UserProfilePage> createState() => UserProfilePageState();
}

class UserProfilePageState extends State<UserProfilePage> {
  bool _isSigningIn = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () {
      setState(() {
        _loading = false;
      });
    });
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
          Navigator.of(
            context,
          ).pushReplacement(
            MaterialPageRoute(builder: (context) => MainPage()),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Sign in cancelled')));
        }
      }
    } catch (error) {
      debugPrint('Sign in failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(content: Text('Something went wrong')),
        );
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
    } catch (error) {
      debugPrint('Google sign out failed: $error');
      // Ignore Google sign-out failures.
    }

    try {
      await widget.auth.signOut();
    } catch (error) {
      debugPrint('Firebase sign out failed: $error');
      // Ignore Firebase sign-out failures.
    }

    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => MainPage()));
  }

  @override
  Widget build(BuildContext context) {
    final googleUser = widget.user;
    final firebaseUser = widget.auth.currentUser;
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        'Profile',
        actions: [
          if (widget.auth.currentUser != null)
            NotificationButton(
              service: NotificationService(firestore: widget.firestore),
              auth: widget.auth,
            ),
        ],
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: Center(
          child: () {
            return _loading
                ? const CircularProgressIndicator()
                : ((firebaseUser == null && googleUser == null)
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton(
                            onPressed: _isSigningIn
                                ? null
                                : () async => await _handleSignIn(),
                            child: _isSigningIn
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Sign in with Google'),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => LoginPage(auth: widget.auth),
                                ),
                              );
                            },
                            child: const Text('Email Sign In'),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => SignupPage(
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
                              CircleAvatar(
                                backgroundImage: NetworkImage(photoUrl),
                                radius: 40,
                              ),
                            const SizedBox(height: 16),
                            Text(
                              displayName,
                              style: Theme.of(context).textTheme.headlineSmall,
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
                            ElevatedButton(
                              onPressed: () async => _handleSignOut(),
                              child: const Text('Sign Out'),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => NotificationSettingsPage(),
                                  ),
                                );
                              },
                              child: const Text('Notification Settings'),
                            ),
                          ],
                        );
                      }());
          }(),
        ),
      ),
    );
  }
}
