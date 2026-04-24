import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:bible_read/pages/login_page.dart';
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

class AuthSelectionPage extends StatefulWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final GoogleSignIn Function() googleSignInProvider;
  final VibrationService vibrationService;
  final Widget Function(BuildContext)? mainPageBuilder;

  AuthSelectionPage({
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
  State<AuthSelectionPage> createState() => _AuthSelectionPageState();
}

class _AuthSelectionPageState extends State<AuthSelectionPage> {
  bool _isSigningIn = false;

  Future<void> _handleGoogleSignIn() async {
    if (_isSigningIn) return;

    setState(() {
      _isSigningIn = true;
    });

    unawaited(widget.vibrationService.lightImpact());

    try {
      final GoogleSignIn googleSignIn = widget.googleSignInProvider();
      final GoogleSignInAccount account = await googleSignIn.authenticate();

      final GoogleSignInAuthentication auth = account.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: auth.idToken,
      );

      await widget.auth.signInWithCredential(credential);
    } catch (error, st) {
      if (error is GoogleSignInException &&
          error.code == GoogleSignInExceptionCode.canceled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sign in cancelled')),
          );
        }
      } else {
        if (kDebugMode) {
          debugPrint('Sign in failed: $error');
        }
        ErrorLogger.log(error, st);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Something went wrong')),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141218), // m3-dark-surface
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl:
                  'https://lh3.googleusercontent.com/aida-public/AB6AXuCfzrtAkMN22RwB2ZiqvZ7-a-u3c-1Q3SYe1V6xrgX8oGAGl0fcdKTFGezJhbpHXu8o1n3ePffi_ZF79ajNqZfUsXddI-13tqUsvWaaiNgLKefDYXK0KgRmpDPKA_meuN2OR1SNZqMAEjz6CXvzG7W7A6V3Do9bc_HOxoFH-5RLqbVZek6jTgqM-ERrpHdie1ASqWaBbJxXCKiQDVcL0TkaFmAp07o9oaHvgLprritLLT8kmwNubpE4Xl6s2ETlB0C7b6HWAgBESSe6',
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(color: Colors.black),
              errorWidget: (context, url, error) =>
                  Container(color: const Color(0xFF141218)),
            ),
          ),
          // Gradient 1 (Purple/Indigo overlay)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    const Color(0xFF1D0033),
                    const Color(0xFF2A0038).withValues(alpha: 0.9),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),
          // Gradient 2 (Black fade)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.3, 1.0],
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  // Push content to bottom
                  const Spacer(),

                  // Title
                  Text(
                    'Join the Community',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          offset: const Offset(0, 2),
                          blurRadius: 4,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Description
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'Sign up to track your progress and connect with your reading group.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFFCAC4D0),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Continue with Google Button
                  SizedBox(
                    height: 56,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _handleGoogleSignIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        elevation: 4,
                        shadowColor: Colors.black.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: _isSigningIn
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const FaIcon(FontAwesomeIcons.google,
                                    size: 20, color: Colors.black),
                                const SizedBox(width: 12),
                                Text(
                                  'Continue with Google',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Sign up with email Button
                  SizedBox(
                    height: 56,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        unawaited(widget.vibrationService.mediumImpact());
                        Navigator.of(context).push(
                          animatedPageRoute(
                            SignupPage(
                              auth: widget.auth,
                              firestore: widget.firestore,
                              googleSignInProvider: widget.googleSignInProvider,
                              mainPageBuilder: widget.mainPageBuilder,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFFD0BCFF), // m3-dark-primary
                        foregroundColor:
                            const Color(0xFF381E72), // m3-dark-on-primary
                        elevation: 4,
                        shadowColor: Colors.black.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.mail_outline, size: 24),
                          const SizedBox(width: 12),
                          Text(
                            'Sign up with email',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Login Link
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
                                googleSignInProvider:
                                    widget.googleSignInProvider,
                              ),
                            ),
                          );
                        },
                        child: Text(
                          'Log in',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFD0BCFF),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Bottom Padding
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
