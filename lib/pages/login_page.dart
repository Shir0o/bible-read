import 'dart:async';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/signup_page.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:bible_read/services/google_sign_in_factory.dart';
import 'package:bible_read/services/vibration_service.dart';
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

  @override
  Widget build(BuildContext context) {
    const darkPrimary = Color(0xFFD0BCFF);
    const m3PrimaryContainer = Color(0xFFEADDFF);
    const m3OnPrimaryContainer = Color(0xFF21005D);
    const m3SurfaceDim = Color(0xFFDED8E1);
    const m3SurfaceBright = Color(0xFFFEF7FF);

    return Scaffold(
      backgroundColor: const Color(0xFF141218),
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.network(
              'https://lh3.googleusercontent.com/aida-public/AB6AXuCfzrtAkMN22RwB2ZiqvZ7-a-u3c-1Q3SYe1V6xrgX8oGAGl0fcdKTFGezJhbpHXu8o1n3ePffi_ZF79ajNqZfUsXddI-13tqUsvWaaiNgLKefDYXK0KgRmpDPKA_meuN2OR1SNZqMAEjz6CXvzG7W7A6V3Do9bc_HOxoFH-5RLqbVZek6jTgqM-ERrpHdie1ASqWaBbJxXCKiQDVcL0TkaFmAp07o9oaHvgLprritLLT8kmwNubpE4Xl6s2ETlB0C7b6HWAgBESSe6',
              fit: BoxFit.cover,
            ),
          ),
          // Gradient 1
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    const Color(0xFF1D0033),
                    const Color(0xFF2A0038).withValues(alpha: 0.95),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Gradient 2 (Dark overlay)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.9),
                    Colors.black.withValues(alpha: 0.6),
                    Colors.black.withValues(alpha: 0.2),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  // Icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: m3PrimaryContainer,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ]),
                    child: Icon(Icons.menu_book,
                        color: m3OnPrimaryContainer, size: 24),
                  ),
                  const SizedBox(height: 16),
                  // Title
                  Text(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 30, // 3xl
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.1,
                      letterSpacing: -0.025,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Subtitle
                  Text(
                    'Sign in to continue your journey',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: m3SurfaceDim.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Form
                  AutofillGroup(
                    child: Column(
                      children: [
                        // Email
                        Container(
                          decoration: BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: m3SurfaceDim.withValues(
                                          alpha: 0.4)))),
                          child: Stack(
                            children: [
                              Container(
                                height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(8)),
                                ),
                              ),
                              TextFormField(
                                key: const Key('loginEmailField'),
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                textInputAction: TextInputAction.next,
                                style:
                                    GoogleFonts.inter(color: m3SurfaceBright),
                                decoration: InputDecoration(
                                  labelText: 'Email or Username',
                                  labelStyle: GoogleFonts.inter(
                                      color:
                                          m3SurfaceDim.withValues(alpha: 0.7)),
                                  floatingLabelStyle:
                                      GoogleFonts.inter(color: darkPrimary),
                                  border: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.fromLTRB(16, 24, 16, 8),
                                  isDense: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Password
                        Container(
                          decoration: BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: m3SurfaceDim.withValues(
                                          alpha: 0.4)))),
                          child: Stack(
                            children: [
                              Container(
                                height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(8)),
                                ),
                              ),
                              TextFormField(
                                key: const Key('loginPasswordField'),
                                controller: _passwordController,
                                obscureText: !_isPasswordVisible,
                                autofillHints: const [AutofillHints.password],
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                style:
                                    GoogleFonts.inter(color: m3SurfaceBright),
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  labelStyle: GoogleFonts.inter(
                                      color:
                                          m3SurfaceDim.withValues(alpha: 0.7)),
                                  floatingLabelStyle:
                                      GoogleFonts.inter(color: darkPrimary),
                                  border: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.fromLTRB(16, 24, 48, 8),
                                  isDense: true,
                                  suffixIcon: IconButton(
                                    tooltip: _isPasswordVisible
                                        ? 'Hide password'
                                        : 'Show password',
                                    icon: Icon(
                                      _isPasswordVisible
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color:
                                          m3SurfaceDim.withValues(alpha: 0.6),
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _isPasswordVisible =
                                            !_isPasswordVisible;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Forgot Password
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        // TODO: Implement forgot password
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Not implemented yet')),
                        );
                      },
                      child: Text(
                        'Forgot Password?',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: darkPrimary,
                        ),
                      ),
                    ),
                  ),

                  // Login Button
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: m3PrimaryContainer,
                        foregroundColor: m3OnPrimaryContainer,
                        elevation: 4,
                        shadowColor: Colors.black.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: _loading
                          ? SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: m3OnPrimaryContainer))
                          : Text(
                              'Login',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                    ),
                  ),

                  // Or Divider
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Row(
                      children: [
                        Expanded(
                            child: Divider(
                                color: m3SurfaceDim.withValues(alpha: 0.2))),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'or',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: m3SurfaceDim.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        Expanded(
                            child: Divider(
                                color: m3SurfaceDim.withValues(alpha: 0.2))),
                      ],
                    ),
                  ),

                  // Google Button
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _handleGoogleSignIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1F1F1F),
                        elevation: 1,
                        shadowColor: Colors.black.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: _isGoogleSigningIn
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF1F1F1F)))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const FaIcon(FontAwesomeIcons.google,
                                    size: 20, color: Color(0xFF1F1F1F)),
                                const SizedBox(width: 12),
                                Text(
                                  'Sign in with Google',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const Spacer(),

                  // Sign up link
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24.0, top: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: m3SurfaceDim,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            unawaited(widget.vibrationService.lightImpact());
                            Navigator.of(context).push(
                              animatedPageRoute(
                                SignupPage(
                                  auth: widget.auth,
                                  firestore: widget.firestore,
                                  googleSignInProvider:
                                      widget.googleSignInProvider,
                                  mainPageBuilder: widget.mainPageBuilder,
                                ),
                              ),
                            );
                          },
                          child: Text(
                            'Sign up',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: darkPrimary,
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
        ],
      ),
    );
  }
}
