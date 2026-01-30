import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/signup_form.dart';
import 'main_page.dart';

/// Page that hosts the [SignupForm] widget for creating a new account.
class SignupPage extends StatefulWidget {
  /// Auth instance used to create the account.
  final FirebaseAuth auth;

  /// Firestore instance used to store user data.
  final FirebaseFirestore firestore;

  /// Service used to trigger vibrations.
  final VibrationService vibrationService;

  /// Optional builder for MainPage to facilitate testing.
  final Widget Function(BuildContext)? mainPageBuilder;

  /// Creates a [SignupPage].
  SignupPage({
    super.key,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    VibrationService? vibrationService,
    this.mainPageBuilder,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        vibrationService = vibrationService ?? const VibrationService();

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar(context, 'Sign Up'),
      body: Container(
        decoration:
            CommonStyles.backgroundDecoration(Theme.of(context).colorScheme),
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: SignupForm(
            auth: widget.auth,
            firestore: widget.firestore,
            onComplete: () {
              unawaited(widget.vibrationService.mediumImpact());
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: widget.mainPageBuilder ?? (_) => MainPage(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
