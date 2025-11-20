import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
  bool _monthlySummaryEnabled = true;

  void _handleSignupError(Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('Failed to sign up: $error');
    }
    ErrorLogger.log(error, stackTrace);
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
        _handleSignupError(
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
        'emailPrefs': {'monthlySummary': _monthlySummaryEnabled},
      });
      if (mounted) {
        SuccessAnimation.show(
          context,
          vibrationService: widget.vibrationService,
        );
        widget.onComplete?.call();
      }
    } catch (e, st) {
      _handleSignupError(e, st);
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('signupEmailField'),
          controller: _emailController,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('signupPasswordField'),
          controller: _passwordController,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('signupConfirmField'),
          controller: _confirmController,
          decoration: const InputDecoration(labelText: 'Confirm Password'),
          obscureText: true,
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _monthlySummaryEnabled,
          onChanged: (value) {
            setState(() {
              _monthlySummaryEnabled = value ?? true;
            });
          },
          title: const Text('Receive monthly summary emails'),
          subtitle: const Text(
            'We will email you a monthly summary of your reading progress. '
            'You can opt out anytime in your profile settings.',
          ),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 8),
        AnimatedActionButton(
          onPressed: _submit,
          isLoading: _loading,
          vibrationService: widget.vibrationService,
          child: const Text('Sign Up'),
        ),
      ],
    );
  }
}
