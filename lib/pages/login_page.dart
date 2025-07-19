import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/common_styles.dart';
import '../widgets/login_form.dart';
import 'main_page.dart';

/// Page that hosts the [LoginForm] widget for email/password sign in.
class LoginPage extends StatefulWidget {
  /// Auth instance used to sign in.
  final FirebaseAuth auth;

  /// Creates a [LoginPage].
  LoginPage({super.key, FirebaseAuth? auth})
      : auth = auth ?? FirebaseAuth.instance;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar('Sign In'),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: LoginForm(
            auth: widget.auth,
            onComplete: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => MainPage()),
              );
            },
          ),
        ),
      ),
    );
  }
}
