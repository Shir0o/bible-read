import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../widgets/common_styles.dart';
import 'main_page.dart';

class UserProfilePage extends StatefulWidget {
  final GoogleSignInAccount? user;
  final GoogleSignIn Function() googleSignInProvider;
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  UserProfilePage({
    super.key,
    this.user,
    GoogleSignIn Function()? googleSignInProvider,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : googleSignInProvider = googleSignInProvider ?? GoogleSignIn.new,
        firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance;

  @override
  State<UserProfilePage> createState() => UserProfilePageState();
}

class UserProfilePageState extends State<UserProfilePage> {
  bool _isSigningIn = false;
  bool _loading = true;

  Future<void> _handleSignOut() async {
    await widget.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MainPage()),
    );
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content:
            const Text('This will permanently delete your account. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final user = widget.auth.currentUser;
      if (user != null) {
        await widget.firestore.collection('users').doc(user.uid).delete();
        await user.delete();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        if (e.code == 'requires-recent-login') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please sign in again to delete your account.'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: ${e.message ?? e.code}')),
          );
        }
      }
      return;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MainPage()),
    );
  }

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
    setState(() {
      _isSigningIn = true;
    });
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

        if (!mounted) return;
        setState(() {
          // Update the user passed from parent by calling widget.user is final, so we can't update it directly
          // Instead, rebuild parent or manage user state differently if needed
          // For now, just rebuild to reflect sign in
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => MainPage(),
            ),
          );
        });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in cancelled')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign in failed: $error')),
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

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Scaffold(
      appBar: CommonStyles.buildAppBar('Profile'),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : (user == null
                  ? ElevatedButton(
                      onPressed: _isSigningIn
                          ? null
                          : () async => await _handleSignIn(),
                      child: _isSigningIn
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in with Google'),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (user.photoUrl != null)
                          CircleAvatar(
                            backgroundImage: NetworkImage(user.photoUrl!),
                            radius: 40,
                          ),
                        const SizedBox(height: 16),
                        Text(
                          user.displayName ?? 'No Name',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          user.email,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _handleSignOut,
                          child: const Text('Sign Out'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _deleteAccount,
                          child: const Text('Delete Account'),
                        ),
                      ],
                    )),
        ),
      ),
    );
  }
}
