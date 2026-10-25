import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../pages/login_page.dart';
import '../pages/signup_page.dart';
import '../services/account_linking_service.dart';
import '../services/apple_sign_in_service.dart';
import '../services/error_logger.dart';
import '../services/google_sign_in_factory.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import 'animated_page_route.dart';
import 'app_bottom_sheet.dart';
import 'auth/apple_sign_in_button.dart';
import 'merge_dry_run_sheet.dart';

/// Displays the Sanctuary Liturgy modal sheet prompting guest readers to sign in
/// or link an account when accessing social surfaces.
Future<T?> showGuestAccountSheet<T>(
  BuildContext context, {
  FirebaseAuth? auth,
  FirebaseFirestore? firestore,
  AccountLinkingService? accountLinkingService,
  GoogleSignIn Function()? googleSignInProvider,
  AppleSignInService? appleSignInService,
  VibrationService? vibrationService,
}) async {
  final linkingService = accountLinkingService ??
      AccountLinkingService(
        auth: auth ?? FirebaseAuth.instance,
        firestore: firestore ?? FirebaseFirestore.instance,
      );

  final result = await showAppSheet<dynamic>(
    context: context,
    builder: (sheetContext) => GuestAccountSheet(
      auth: auth,
      firestore: firestore,
      accountLinkingService: linkingService,
      googleSignInProvider: googleSignInProvider,
      appleSignInService: appleSignInService,
      vibrationService: vibrationService,
    ),
  );

  if (result is AccountCollisionException && context.mounted) {
    await showMergeDryRunSheet(
      context: context,
      dryRunData: result.dryRunData,
      accountLinkingService: linkingService,
      vibrationService: vibrationService,
    );
    return null;
  }

  return result as T?;
}

/// Sanctuary Liturgy bottom sheet explaining the benefits of creating or linking
/// an account while preserving local reading streaks and history.
class GuestAccountSheet extends StatefulWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final AccountLinkingService accountLinkingService;
  final GoogleSignIn Function() googleSignInProvider;
  final AppleSignInService appleSignInService;
  final VibrationService vibrationService;
  final void Function(AccountCollisionException collision)? onCollision;

  GuestAccountSheet({
    super.key,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    AccountLinkingService? accountLinkingService,
    GoogleSignIn Function()? googleSignInProvider,
    AppleSignInService? appleSignInService,
    VibrationService? vibrationService,
    this.onCollision,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        accountLinkingService = accountLinkingService ??
            AccountLinkingService(
              auth: auth ?? FirebaseAuth.instance,
              firestore: firestore ?? FirebaseFirestore.instance,
            ),
        googleSignInProvider = googleSignInProvider ?? createGoogleSignIn,
        appleSignInService = appleSignInService ??
            DefaultAppleSignInService(
              auth: auth ?? FirebaseAuth.instance,
              firestore: firestore ?? FirebaseFirestore.instance,
            ),
        vibrationService = vibrationService ?? const VibrationService();

  @override
  State<GuestAccountSheet> createState() => _GuestAccountSheetState();
}

class _GuestAccountSheetState extends State<GuestAccountSheet> {
  bool _isSigningIn = false;

  Future<void> _handleGoogleSignIn() async {
    if (_isSigningIn) return;
    setState(() => _isSigningIn = true);
    unawaited(widget.vibrationService.lightImpact());

    try {
      final googleSignIn = widget.googleSignInProvider();
      final account = await googleSignIn.authenticate();
      final auth = account.authentication;
      final credential = GoogleAuthProvider.credential(idToken: auth.idToken);

      final currentUser = widget.auth.currentUser;
      if (currentUser != null && currentUser.isAnonymous) {
        try {
          await widget.accountLinkingService.linkCredential(credential);
        } on AccountCollisionException catch (e) {
          if (mounted) {
            if (widget.onCollision != null) {
              widget.onCollision!(e);
            } else {
              Navigator.of(context).pop(e);
            }
            return;
          }
        }
      } else {
        await widget.auth.signInWithCredential(credential);
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e, st) {
      if (e is GoogleSignInException &&
          e.code == GoogleSignInExceptionCode.canceled) {
        // User cancelled, do nothing.
      } else {
        ErrorLogger.log(e, st);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sign in failed. Please try again.')),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  Future<void> _handleAppleSignIn() async {
    if (_isSigningIn) return;
    setState(() => _isSigningIn = true);
    unawaited(widget.vibrationService.lightImpact());

    try {
      final appleCred = await widget.appleSignInService.getCredential();
      if (appleCred != null) {
        final currentUser = widget.auth.currentUser;
        if (currentUser != null && currentUser.isAnonymous) {
          try {
            await widget.accountLinkingService.linkCredential(appleCred);
            if (mounted) {
              Navigator.of(context).pop();
            }
            return;
          } on AccountCollisionException catch (e) {
            if (mounted) {
              if (widget.onCollision != null) {
                widget.onCollision!(e);
              } else {
                Navigator.of(context).pop(e);
              }
              return;
            }
          }
        } else {
          await widget.auth.signInWithCredential(appleCred);
          if (mounted) {
            Navigator.of(context).pop();
          }
          return;
        }
      } else {
        final credential = await widget.appleSignInService.signIn();
        if (credential != null && mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.hPadding,
        AppSpacing.gap12,
        AppSpacing.hPadding,
        AppSpacing.gap32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people_alt_outlined,
                color: colorScheme.primary,
                size: 26,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.gap16),
          Text(
            'Read alongside others',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFamily: AppTheme.fontSerif,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.gap8),
          Text(
            'Sign in to connect with friends, join groups, and share your daily reflections.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.gap24),
          if (widget.appleSignInService.isSupported) ...[
            AppleSignInButton(
              service: widget.appleSignInService,
              onPressed: _handleAppleSignIn,
            ),
            const SizedBox(height: AppSpacing.gap12),
          ],
          SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: _isSigningIn ? null : _handleGoogleSignIn,
              child: _isSigningIn
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        // token-exempt: button submitting
                        strokeWidth: 2,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const FaIcon(FontAwesomeIcons.google, size: 18),
                        const SizedBox(width: AppSpacing.gap12),
                        Text(
                          'Continue with Google',
                          style: theme.textTheme.labelLarge,
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.gap12),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  animatedPageRoute(
                    LoginPage(
                      auth: widget.auth,
                      firestore: widget.firestore,
                      googleSignInProvider: widget.googleSignInProvider,
                      vibrationService: widget.vibrationService,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.mail_outline, size: 20),
              label: const Text('Sign in with email'),
            ),
          ),
          const SizedBox(height: AppSpacing.gap8),
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  animatedPageRoute(
                    SignupPage(
                      auth: widget.auth,
                      firestore: widget.firestore,
                      googleSignInProvider: widget.googleSignInProvider,
                    ),
                  ),
                );
              },
              child: Text(
                'Create an account with email',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.gap16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.gap6),
              Flexible(
                child: Text(
                  'Your reading history and streak will be preserved.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
