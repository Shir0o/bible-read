import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import '../services/error_logger.dart';
import 'animated_action_button.dart';
import 'success_animation.dart';
import '../services/vibration_service.dart';

/// Form widget used to sign up a new user with email and password.
class SignupForm extends StatefulWidget {
  /// Auth instance used to create the account.
  final FirebaseAuth auth;

  /// Firestore instance used to store the user document.
  final FirebaseFirestore firestore;

  /// Optional callback invoked when the sign up completes successfully.
  final VoidCallback? onComplete;

  /// Service used for celebratory haptic feedback.
  final VibrationService vibrationService;

  /// Creates a [SignupForm].
  const SignupForm({
    super.key,
    required this.auth,
    required this.firestore,
    this.onComplete,
    VibrationService? vibrationService,
  }) : vibrationService = vibrationService ?? const VibrationService();

  @override
  State<SignupForm> createState() => _SignupFormState();
}

class _SignupFormState extends State<SignupForm> {
  static const _failureSnackBar = SnackBar(
    content: Text('Failed to sign up. Please try again.'),
  );

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _loading = false;

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  Future<void> _handleSignupError(Object error, StackTrace stackTrace) async {
    await ErrorLogger.log(error, stackTrace);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(_failureSnackBar);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (email.isEmpty || password.isEmpty || confirm.isEmpty) return;
    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }
    setState(() {
      _loading = true;
    });
    try {
      final credential = await widget.auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        await _handleSignupError(
          FirebaseAuthException(
            code: 'missing-user',
            message: 'Auth returned a null user after sign up.',
          ),
          StackTrace.current,
        );
        return;
      }
      await widget.firestore.collection('users').doc(user.uid).set({
        'name': user.displayName ?? '',
        'email': user.email?.toLowerCase(),
      });

      if (mounted) {
        unawaited(SuccessAnimation.show(
          context,
          vibrationService: widget.vibrationService,
        ));
        widget.onComplete?.call();
      }
    } catch (e, st) {
      await _handleSignupError(e, st);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('signupEmailField'),
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('signupPasswordField'),
            controller: _passwordController,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                tooltip: _isPasswordVisible ? 'Hide password' : 'Show password',
                icon: Icon(
                  _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    _isPasswordVisible = !_isPasswordVisible;
                  });
                },
              ),
            ),
            obscureText: !_isPasswordVisible,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('signupConfirmField'),
            controller: _confirmController,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Confirm Password',
              suffixIcon: IconButton(
                tooltip: _isConfirmPasswordVisible
                    ? 'Hide password'
                    : 'Show password',
                icon: Icon(
                  _isConfirmPasswordVisible
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                  });
                },
              ),
            ),
            obscureText: !_isConfirmPasswordVisible,
          ),

          const SizedBox(height: 8),
          AnimatedActionButton(
            onPressed: _submit,
            isLoading: _loading,
            vibrationService: widget.vibrationService,
            child: const Text('Sign Up'),
          ),
        ],
      ),
    );
  }
}
