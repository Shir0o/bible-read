import 'dart:async';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/signup_page.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:bible_read/services/google_sign_in_factory.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/theme/app_theme.dart';
import 'package:bible_read/widgets/animated_page_route.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginPage extends StatefulWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final GoogleSignIn Function() googleSignInProvider;
  final VibrationService vibrationService;
  final Widget Function(BuildContext)? mainPageBuilder;

  LoginPage({
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
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _loading = false;
  bool _isGoogleSigningIn = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(
            r"^[a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9-]+\.[a-zA-Z]+$")
        .hasMatch(email);
  }

  Future<void> _submit() async {
    if (_loading || _isGoogleSigningIn) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')),
      );
      return;
    }

    setState(() {
      _loading = true;
    });

    unawaited(widget.vibrationService.mediumImpact());

    try {
      await widget.auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: widget.mainPageBuilder ?? (_) => MainPage(),
          ),
          (route) => false,
        );
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

  Future<void> _handleForgotPassword() async {
    final initialEmail =
        _isValidEmail(_emailController.text) ? _emailController.text : '';

    await showDialog(
      context: context,
      builder: (context) {
        return _ForgotPasswordDialog(
          auth: widget.auth,
          initialEmail: initialEmail,
          vibrationService: widget.vibrationService,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.m3DarkSurface,
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.network(
              'https://lh3.googleusercontent.com/aida-public/AB6AXuCfzrtAkMN22RwB2ZiqvZ7-a-u3c-1Q3SYe1V6xrgX8oGAGl0fcdKTFGezJhbpHXu8o1n3ePffi_ZF79ajNqZfUsXddI-13tqUsvWaaiNgLKefDYXK0KgRmpDPKA_meuN2OR1SNZqMAEjz6CXvzG7W7A6V3Do9bc_HOxoFH-5RLqbVZek6jTgqM-ERrpHdie1ASqWaBbJxXCKiQDVcL0TkaFmAp07o9oaHvgLprritLLT8kmwNubpE4Xl6s2ETlB0C7b6HWAgBESSe6',
              fit: BoxFit.cover,
            ),
          ),
          // Gradient 1 (Dark Overlay)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    const Color(0xFF141218), // m3-dark-surface
                    const Color(0xFF141218).withValues(alpha: 0.9),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Black Overlay
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.4),
            ),
          ),

          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 40),
                          // Header Icon
                          Container(
                            width: 64, // h-16
                            height: 64, // w-16
                            decoration: BoxDecoration(
                              color: AppTheme.m3Primary,
                              borderRadius:
                                  BorderRadius.circular(16), // rounded-2xl
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                      alpha:
                                          0.25), // shadow-2xl equivalent approx
                                  blurRadius: 25,
                                  offset: const Offset(0, 25),
                                )
                              ],
                            ),
                            child: const Icon(Icons.menu_book,
                                color: AppTheme.m3OnPrimary,
                                size: 36), // text-4xl
                          ),
                          const SizedBox(
                              height:
                                  24), // mb-10 in HTML, but here we stack elements

                          // Title
                          Text(
                            'Welcome back',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 30, // 3xl
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.25, // leading-tight
                              letterSpacing: -0.025, // tracking-tight
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Subtitle
                          Container(
                            constraints: const BoxConstraints(maxWidth: 280),
                            child: Text(
                              'Join your community in daily Scripture reading',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 16, // text-base
                                color: AppTheme.m3SurfaceDim
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                          const SizedBox(height: 40), // mb-10

                          // Form
                          AutofillGroup(
                            child: Column(
                              children: [
                                // Email or Username
                                _buildStyledInput(
                                  controller: _emailController,
                                  label: 'Email or Username',
                                  key: const Key('loginEmailField'),
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: [AutofillHints.email],
                                  textInputAction: TextInputAction.next,
                                  autofocus: true,
                                ),
                                const SizedBox(height: 16), // gap-4

                                // Password
                                _buildStyledInput(
                                  controller: _passwordController,
                                  label: 'Password',
                                  key: const Key('loginPasswordField'),
                                  obscureText: !_isPasswordVisible,
                                  autofillHints: [AutofillHints.password],
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submit(),
                                  suffixIcon: IconButton(
                                    tooltip: _isPasswordVisible
                                        ? 'Hide password'
                                        : 'Show password',
                                    icon: Icon(
                                      _isPasswordVisible
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: AppTheme.m3SurfaceDim
                                          .withValues(alpha: 0.4),
                                      size: 20, // text-xl
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _isPasswordVisible =
                                            !_isPasswordVisible;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Forgot Password
                          Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                  top: 12.0), // -mt-1 in HTML but cleaner here
                              child: Semantics(
                                key: const Key('forgotPasswordSemantics'),
                                button: true,
                                label: 'Forgot password',
                                excludeSemantics: true,
                                child: Tooltip(
                                  message: 'Forgot password',
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(4),
                                      onTap: () {
                                        unawaited(widget.vibrationService
                                            .lightImpact());
                                        _handleForgotPassword();
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Text(
                                          'Forgot Password?',
                                          style: GoogleFonts.inter(
                                            fontSize: 14, // text-sm
                                            fontWeight: FontWeight
                                                .w600, // font-semibold
                                            color: AppTheme.m3Primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Login Button
                          SizedBox(
                            height: 56, // h-14
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.m3Primary,
                                foregroundColor: AppTheme.m3OnPrimary,
                                elevation: 10, // shadow-lg
                                shadowColor:
                                    Colors.black.withValues(alpha: 0.3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppTheme.m3OnPrimary))
                                  : Text(
                                      'Login',
                                      style: GoogleFonts.inter(
                                        fontSize: 16, // text-base
                                        fontWeight:
                                            FontWeight.bold, // font-bold
                                        letterSpacing: 0.5, // tracking-wide
                                      ),
                                    ),
                            ),
                          ),

                          // OR Divider
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24.0),
                            child: Row(
                              children: [
                                Expanded(
                                    child: Divider(
                                        color: Colors.white
                                            .withValues(alpha: 0.1))),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: Text(
                                    'OR',
                                    style: GoogleFonts.inter(
                                      fontSize: 12, // text-xs
                                      fontWeight: FontWeight.bold, // font-bold
                                      color: AppTheme.m3SurfaceDim
                                          .withValues(alpha: 0.4),
                                      letterSpacing: 1.5, // tracking-widest
                                    ),
                                  ),
                                ),
                                Expanded(
                                    child: Divider(
                                        color: Colors.white
                                            .withValues(alpha: 0.1))),
                              ],
                            ),
                          ),

                          // Continue with Google Button
                          SizedBox(
                            height: 56, // h-14
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _handleGoogleSignIn,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF1F1F1F),
                                elevation: 4, // shadow-md
                                shadowColor:
                                    Colors.black.withValues(alpha: 0.1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                  side: BorderSide(
                                      color:
                                          Colors.grey[200]!), // border-gray-200
                                ),
                              ),
                              child: _isGoogleSigningIn
                                  ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF1F1F1F)))
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        // Google Icon
                                        FaIcon(FontAwesomeIcons.google,
                                            size: 20, color: Color(0xFF1F1F1F)),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Continue with Google',
                                          style: GoogleFonts.inter(
                                            fontSize: 16, // text-base
                                            fontWeight: FontWeight
                                                .w600, // font-semibold
                                            letterSpacing:
                                                -0.025, // tracking-tight
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),

                          const SizedBox(height: 40),

                          // Sign up link
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: 40.0, top: 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Don't have an account? ",
                                  style: GoogleFonts.inter(
                                    fontSize: 14, // text-sm
                                    fontWeight: FontWeight.w500, // font-medium
                                    color: AppTheme.m3SurfaceDim
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                                Semantics(
                                  key: const Key('signUpSemantics'),
                                  button: true,
                                  label: 'Sign up',
                                  excludeSemantics: true,
                                  child: Tooltip(
                                    message: 'Sign up',
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(4),
                                        onTap: () {
                                          unawaited(widget.vibrationService
                                              .lightImpact());
                                          Navigator.of(context).push(
                                            animatedPageRoute(
                                              SignupPage(
                                                auth: widget.auth,
                                                firestore: widget.firestore,
                                                vibrationService:
                                                    widget.vibrationService,
                                                googleSignInProvider:
                                                    widget.googleSignInProvider,
                                                mainPageBuilder:
                                                    widget.mainPageBuilder,
                                              ),
                                            ),
                                          );
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(4.0),
                                          child: Text(
                                            'Sign up',
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight:
                                                  FontWeight.bold, // font-bold
                                              color: AppTheme.m3Primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyledInput({
    required TextEditingController controller,
    required String label,
    Key? key,
    bool obscureText = false,
    TextInputType? keyboardType,
    List<String>? autofillHints,
    TextInputAction? textInputAction,
    bool autofocus = false,
    Widget? suffixIcon,
    ValueChanged<String>? onSubmitted,
  }) {
    // Replicating the HTML style:
    // relative w-full
    // absolute inset-0 bg-white/5 rounded-t-xl pointer-events-none border-b border-white/20
    // input peer block w-full rounded-t-xl border-b-2 border-transparent bg-transparent px-4 pt-6 pb-2 ...
    // label ...

    return Stack(
      children: [
        // Background overlay
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12)), // rounded-t-xl
              border: Border(
                  bottom:
                      BorderSide(color: Colors.white.withValues(alpha: 0.2))),
            ),
          ),
        ),

        // Input
        TextFormField(
          key: key,
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          textInputAction: textInputAction,
          autofocus: autofocus,
          onFieldSubmitted: onSubmitted,
          style: GoogleFonts.inter(color: Colors.white),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: GoogleFonts.inter(
              color: AppTheme.m3SurfaceDim.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
            floatingLabelStyle: GoogleFonts.inter(
              color: AppTheme.m3Primary,
              fontWeight: FontWeight.w500,
            ),
            filled: true,
            fillColor: Colors.transparent,
            border: const UnderlineInputBorder(
              borderSide:
                  BorderSide.none, // Handled by background overlay border
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.transparent, width: 2),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.m3Primary, width: 2),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            contentPadding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  final FirebaseAuth auth;
  final String initialEmail;
  final VibrationService vibrationService;

  const _ForgotPasswordDialog({
    required this.auth,
    required this.initialEmail,
    required this.vibrationService,
  });

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late TextEditingController _controller;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
              'Enter your email address to receive a password reset link.'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _sending ? null : _send,
          child: _sending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send Link'),
        ),
      ],
    );
  }

  Future<void> _send() async {
    final email = _controller.text.trim();
    if (email.isEmpty ||
        !RegExp(r"^[a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9-]+\.[a-zA-Z]+$")
            .hasMatch(email)) {
      unawaited(widget.vibrationService.heavyImpact());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')),
      );
      return;
    }

    setState(() {
      _sending = true;
    });

    try {
      await widget.auth.sendPasswordResetEmail(email: email);
      if (mounted) {
        unawaited(widget.vibrationService.mediumImpact());
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent')),
        );
      }
    } catch (e, st) {
      unawaited(widget.vibrationService.heavyImpact());
      if (kDebugMode) {
        debugPrint('Failed to send reset email: $e');
      }
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to send reset email. Please try again.')),
        );
        setState(() {
          _sending = false;
        });
      }
    }
  }
}
