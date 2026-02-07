import 'dart:async';

import 'package:bible_read/pages/login_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:bible_read/services/google_sign_in_factory.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/animated_page_route.dart';
import 'package:bible_read/widgets/success_animation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

class SignupPage extends StatefulWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final GoogleSignIn Function() googleSignInProvider;
  final VibrationService vibrationService;
  final Widget Function(BuildContext)? mainPageBuilder;

  SignupPage({
    super.key,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn Function()? googleSignInProvider,
    VibrationService? vibrationService,
    this.mainPageBuilder,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        googleSignInProvider = googleSignInProvider ?? createGoogleSignIn,
        vibrationService = vibrationService ?? const VibrationService();

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _loading = false;
  bool _isGoogleSigningIn = false;

  late TapGestureRecognizer _termsRecognizer;
  late TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => _launchUrl('https://example.com/terms');
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => _launchUrl('https://example.com/privacy');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  Future<void> _handleSignupError(Object error, StackTrace stackTrace) async {
    await ErrorLogger.log(error, stackTrace);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Failed to sign up. Please try again.')),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri);
  }

  Future<void> _submit() async {
    if (_loading || _isGoogleSigningIn) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() {
      _loading = true;
    });

    unawaited(widget.vibrationService.mediumImpact());

    try {
      final credential = await widget.auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'missing-user',
          message: 'Auth returned a null user after sign up.',
        );
      }

      await user.updateDisplayName(name);

      await widget.firestore.collection('users').doc(user.uid).set({
        'name': name,
        'email': user.email?.toLowerCase(),
      });

      if (mounted) {
        unawaited(SuccessAnimation.show(
          context,
          vibrationService: widget.vibrationService,
        ));

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: widget.mainPageBuilder ?? (_) => MainPage(),
          ),
          (route) => false,
        );
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

  Future<void> _handleGoogleSignIn() async {
    if (_loading || _isGoogleSigningIn) return;

    setState(() {
      _isGoogleSigningIn = true;
    });

    unawaited(widget.vibrationService.lightImpact());

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

        // Navigation is handled by auth stream listener in MainPage usually,
        // but since we are pushing this page, we might want to pop or replace.
        // If we are here, we are likely not authenticated yet.
        // Once authenticated, MainPage stream builder will update.
        // However, if we pushed this page, we should probably pop/replace to main page.

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: widget.mainPageBuilder ?? (_) => MainPage(),
            ),
            (route) => false,
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sign in cancelled')),
          );
        }
      }
    } catch (error, st) {
      if (kDebugMode) {
        debugPrint('Sign in failed: $error');
      }
      ErrorLogger.log(error, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleSigningIn = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const darkSurface = Color(0xFF141218);
    const darkPrimary = Color(0xFFD0BCFF);
    const darkOnPrimary = Color(0xFF381E72);
    const outlineVariant = Color(0xFFCAC4D0);
    const grey400 = Color(0xFF9CA3AF); // Approximate text-gray-400

    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: outlineVariant, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: darkPrimary, width: 1),
      ),
      labelStyle: GoogleFonts.inter(color: grey400),
      floatingLabelStyle: GoogleFonts.inter(color: darkPrimary),
    );

    return Scaffold(
      backgroundColor: darkSurface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shape: const CircleBorder(),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Sign Up',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48), // Balance the back button
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      'Create your account',
                      style: GoogleFonts.inter(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Join the community to start reading together.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: const Color(0xFFCAC4D0),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Form
                    AutofillGroup(
                      child: Column(
                        children: [
                          // Full Name
                          TextField(
                            controller: _nameController,
                            style: GoogleFonts.inter(color: Colors.white),
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.name],
                            textInputAction: TextInputAction.next,
                            decoration: inputDecoration.copyWith(
                              labelText: 'Full Name',
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Email
                          TextField(
                            key: const Key('signupEmailField'),
                            controller: _emailController,
                            style: GoogleFonts.inter(color: Colors.white),
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            decoration: inputDecoration.copyWith(
                              labelText: 'Email',
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Password
                          TextField(
                            key: const Key('signupPasswordField'),
                            controller: _passwordController,
                            style: GoogleFonts.inter(color: Colors.white),
                            obscureText: !_isPasswordVisible,
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            decoration: inputDecoration.copyWith(
                              labelText: 'Password',
                              suffixIcon: IconButton(
                                tooltip: _isPasswordVisible
                                    ? 'Hide password'
                                    : 'Show password',
                                icon: Icon(
                                  _isPasswordVisible
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: grey400,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Terms
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: RichText(
                        text: TextSpan(
                          style:
                              GoogleFonts.inter(fontSize: 12, color: grey400),
                          children: [
                            const TextSpan(
                                text:
                                    'By creating an account, you agree to our '),
                            TextSpan(
                              text: 'Terms of Service',
                              style: GoogleFonts.inter(
                                color: darkPrimary,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: _termsRecognizer,
                            ),
                            const TextSpan(text: ' and '),
                            TextSpan(
                              text: 'Privacy Policy',
                              style: GoogleFonts.inter(
                                color: darkPrimary,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: _privacyRecognizer,
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Create Account Button
                    SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: darkPrimary,
                          foregroundColor: darkOnPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: darkOnPrimary))
                            : Text(
                                'Create Account',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Or continue with
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey[800])),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        'Or continue with',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: const Color(0xFFCAC4D0),
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey[800])),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Google Button
                  _SocialButton(
                    onTap: _handleGoogleSignIn,
                    label: 'Sign in with Google',
                    child: const FaIcon(FontAwesomeIcons.google,
                        size: 20, color: Colors.white),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Log in link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account? ',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFFCAC4D0),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      unawaited(widget.vibrationService.lightImpact());
                      Navigator.of(context).push(
                        animatedPageRoute(
                          LoginPage(
                            auth: widget.auth,
                            googleSignInProvider: widget.googleSignInProvider,
                          ),
                        ),
                      );
                    },
                    child: Text(
                      'Log in',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: darkPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  final String label;

  const _SocialButton({
    required this.onTap,
    required this.child,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey[800]!),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}
