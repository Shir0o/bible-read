import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/login_form.dart';
import 'main_page.dart';

/// Page that hosts the [LoginForm] widget for email/password sign in.
class LoginPage extends StatefulWidget {
  /// Auth instance used to sign in.
  final FirebaseAuth auth;

  /// Service used to trigger vibrations.
  final VibrationService vibrationService;

  /// Creates a [LoginPage].
  LoginPage({
    super.key,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
  })  : auth = auth ?? FirebaseAuth.instance,
        vibrationService = vibrationService ?? const VibrationService();

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar(context, 'Sign In'),
      body: Container(
        decoration:
            CommonStyles.backgroundDecoration(Theme.of(context).colorScheme),
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: LoginForm(
            auth: widget.auth,
            onComplete: () {
              unawaited(widget.vibrationService.mediumImpact());
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
