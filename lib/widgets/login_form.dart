import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/error_logger.dart';
import 'animated_action_button.dart';

/// Simple email/password sign-in form.
class LoginForm extends StatefulWidget {
  /// Auth instance used to sign in.
  final FirebaseAuth auth;

  /// Optional callback invoked when sign in completes successfully.
  final VoidCallback? onComplete;

  /// Creates a [LoginForm].
  const LoginForm({
    super.key,
    required this.auth,
    this.onComplete,
  });

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;
    setState(() {
      _loading = true;
    });
    try {
      await widget.auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (mounted) {
        widget.onComplete?.call();
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to sign in: $e');
      }
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to sign in. Please check credentials.')),
        );
      }
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
            key: const Key('loginEmailField'),
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('loginPasswordField'),
            controller: _passwordController,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          AnimatedActionButton(
            onPressed: _submit,
            isLoading: _loading,
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }
}
