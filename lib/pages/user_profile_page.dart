import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../widgets/common_styles.dart';
import '../widgets/friend_request_widget.dart';
import '../services/friend_service.dart';
import 'main_page.dart';

class UserProfilePage extends StatefulWidget {
  final GoogleSignInAccount? user;
  final GoogleSignIn Function() googleSignInProvider;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FriendService friendService;

  UserProfilePage({
    super.key,
    this.user,
    GoogleSignIn Function()? googleSignInProvider,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FriendService? friendService,
  })  : googleSignInProvider = googleSignInProvider ?? GoogleSignIn.new,
        auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        friendService = friendService ?? FriendService(firestore: firestore);

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
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Friend Requests',
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 150,
                          child: widget.auth.currentUser == null
                              ? const Text('Please sign in')
                              : FriendRequestWidget(
                                  service: widget.friendService,
                                  currentUid: widget.auth.currentUser!.uid,
                                ),
                        ),
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Friends',
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 150,
                          child: widget.auth.currentUser == null
                              ? const SizedBox.shrink()
                              : StreamBuilder<List<Map<String, dynamic>>>(
                                  stream: widget.friendService
                                      .friends(widget.auth.currentUser!.uid),
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData) {
                                      return const Center(
                                          child: CircularProgressIndicator());
                                    }
                                    final friends = snapshot.data!;
                                    if (friends.isEmpty) {
                                      return const Text('No friends yet');
                                    }
                                    return ListView(
                                      children: friends
                                          .map((f) => ListTile(
                                                title:
                                                    Text(f['name'] ?? f['uid']),
                                              ))
                                          .toList(),
                                    );
                                  },
                                ),
                        ),
                      ],
                    )),
        ),
      ),
    );
  }
}
