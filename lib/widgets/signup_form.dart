import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Form widget used to sign up a new user with email and password.
class SignupForm extends StatefulWidget {
  /// Auth instance used to create the account.
  final FirebaseAuth auth;

  /// Firestore instance used to store the user document.
  final FirebaseFirestore firestore;

  /// Optional callback invoked when the sign up completes successfully.
  final VoidCallback? onComplete;

  /// Creates a [SignupForm].
  const SignupForm({
    super.key,
    required this.auth,
    required this.firestore,
    this.onComplete,
  });

  @override
  State<SignupForm> createState() => _SignupFormState();
}

class _SignupFormState extends State<SignupForm> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _loading = false;

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
      if (user != null) {
        await widget.firestore.collection('users').doc(user.uid).set({
          'name': user.displayName ?? '',
          'email': user.email?.toLowerCase(),
        });
      }
      if (mounted) {
        widget.onComplete?.call();
      }
    } catch (e) {
      debugPrint('Failed to sign up: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to sign up. Please try again.')),
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
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Sign Up'),
        ),
      ],
    );
  }
}
