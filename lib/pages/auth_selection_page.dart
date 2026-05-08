import 'dart:async';

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
import 'package:google_sign_in/google_sign_in.dart';

import '../widgets/auth/auth_background.dart';

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
    return AuthBackground(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              // Push content to bottom
              const Spacer(),

              // Title
              Text(
                'Join the Community',
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                  color: colorScheme.onSurface,
                  shadows: [
                    Shadow(
                      offset: const Offset(0, 2),
                      blurRadius: 4,
                      color: colorScheme.scrim.withValues(alpha: 0.5),
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
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colorScheme.onSurfaceVariant,
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
                    backgroundColor: colorScheme.surfaceBright,
                    foregroundColor: colorScheme.onSurface,
                    elevation: 4,
                    shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: _isSigningIn
                      ? SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: colorScheme.onSurface))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const FaIcon(FontAwesomeIcons.google, size: 20),
                            const SizedBox(width: 12),
                            Text(
                              'Continue with Google',
                              style: textTheme.titleSmall?.copyWith(
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
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    elevation: 4,
                    shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
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
                        style: textTheme.titleSmall?.copyWith(
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
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  InkWell(
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
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8.0, vertical: 4.0),
                      child: Text(
                        'Log in',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Bottom Padding
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}
