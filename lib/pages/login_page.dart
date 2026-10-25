import 'dart:async';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/signup_page.dart';
import 'package:bible_read/services/account_linking_service.dart';
import 'package:bible_read/services/apple_sign_in_service.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:bible_read/services/google_sign_in_factory.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/theme/app_theme.dart';
import 'package:bible_read/widgets/animated_page_route.dart';
import 'package:bible_read/widgets/auth/apple_sign_in_button.dart';
import 'package:bible_read/widgets/auth/auth_background.dart';
import 'package:bible_read/widgets/merge_dry_run_sheet.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginPage extends StatefulWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final GoogleSignIn Function() googleSignInProvider;
  final AppleSignInService appleSignInService;
  final VibrationService vibrationService;
  final BaseCacheManager? cacheManager;
  final Widget Function(BuildContext)? mainPageBuilder;

  LoginPage({
    super.key,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn Function()? googleSignInProvider,
    AppleSignInService? appleSignInService,
    VibrationService? vibrationService,
    this.cacheManager,
    this.mainPageBuilder,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        googleSignInProvider = googleSignInProvider ?? createGoogleSignIn,
        appleSignInService = appleSignInService ??
            DefaultAppleSignInService(
              auth: auth,
              firestore: firestore,
            ),
        vibrationService = vibrationService ?? const VibrationService();

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _loading = false;
  bool _isGoogleSigningIn = false;
  bool _isAppleSigningIn = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(
      r"^[a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9-]+\.[a-zA-Z]+$",
    ).hasMatch(email);
  }

  Future<void> _submit() async {
    if (_loading || _isGoogleSigningIn) return;

    if (!_formKey.currentState!.validate()) {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      if (email.isEmpty || password.isEmpty) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all fields')),
        );
      } else if (!_isValidEmail(email)) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid email address')),
        );
      }
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _loading = true;
    });

    unawaited(widget.vibrationService.mediumImpact());

    try {
      final currentUser = widget.auth.currentUser;
      if (currentUser != null && currentUser.isAnonymous) {
        final credential = EmailAuthProvider.credential(
          email: email,
          password: password,
        );
        final linkingService = AccountLinkingService(
          auth: widget.auth,
          firestore: widget.firestore,
        );
        try {
          await linkingService.linkCredential(credential);
        } on AccountCollisionException catch (e) {
          if (mounted) {
            await showMergeDryRunSheet(
              context: context,
              dryRunData: e.dryRunData,
              accountLinkingService: linkingService,
              vibrationService: widget.vibrationService,
            );
          }
        }
      } else {
        await widget.auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: widget.mainPageBuilder ??
                  (_) => MainPage(
                        auth: widget.auth,
                        firestore: widget.firestore,
                        googleSignInProvider: widget.googleSignInProvider,
                        vibrationService: widget.vibrationService,
                      ),
            ),
            (route) => false,
          );
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to sign in: $e');
      }
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to sign in. Please check credentials.'),
          ),
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
      final GoogleSignInAccount account = await googleSignIn.authenticate();

      final GoogleSignInAuthentication auth = account.authentication;
      final credential = GoogleAuthProvider.credential(idToken: auth.idToken);

      final currentUser = widget.auth.currentUser;
      if (currentUser != null && currentUser.isAnonymous) {
        final linkingService = AccountLinkingService(
          auth: widget.auth,
          firestore: widget.firestore,
        );
        try {
          await linkingService.linkCredential(credential);
        } on AccountCollisionException catch (e) {
          if (mounted) {
            await showMergeDryRunSheet(
              context: context,
              dryRunData: e.dryRunData,
              accountLinkingService: linkingService,
              vibrationService: widget.vibrationService,
            );
          }
        }
      } else {
        await widget.auth.signInWithCredential(credential);
      }

      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: widget.mainPageBuilder ??
                  (_) => MainPage(
                        auth: widget.auth,
                        firestore: widget.firestore,
                        googleSignInProvider: widget.googleSignInProvider,
                        vibrationService: widget.vibrationService,
                      ),
            ),
            (route) => false,
          );
        }
      }
    } catch (error, st) {
      if (error is GoogleSignInException &&
          error.code == GoogleSignInExceptionCode.canceled) {
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Sign in cancelled')));
        }
      } else {
        if (kDebugMode) {
          debugPrint('Sign in failed: $error');
        }
        ErrorLogger.log(error, st);
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Something went wrong')));
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleSigningIn = false;
        });
      }
    }
  }

  Future<void> _handleAppleSignIn() async {
    if (_loading || _isGoogleSigningIn || _isAppleSigningIn) return;

    setState(() {
      _isAppleSigningIn = true;
    });

    unawaited(widget.vibrationService.lightImpact());

    try {
      final appleCred = await widget.appleSignInService.getCredential();
      if (appleCred != null) {
        final currentUser = widget.auth.currentUser;
        if (currentUser != null && currentUser.isAnonymous) {
          final linkingService = AccountLinkingService(
            auth: widget.auth,
            firestore: widget.firestore,
          );
          try {
            await linkingService.linkCredential(appleCred);
          } on AccountCollisionException catch (e) {
            if (mounted) {
              await showMergeDryRunSheet(
                context: context,
                dryRunData: e.dryRunData,
                accountLinkingService: linkingService,
                vibrationService: widget.vibrationService,
              );
            }
          }
        } else {
          await widget.auth.signInWithCredential(appleCred);
        }
      } else {
        final credential = await widget.appleSignInService.signIn();
        if (credential == null) {
          // Cancelled by user
          return;
        }
      }

      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: widget.mainPageBuilder ??
                  (_) => MainPage(
                        auth: widget.auth,
                        firestore: widget.firestore,
                        googleSignInProvider: widget.googleSignInProvider,
                        vibrationService: widget.vibrationService,
                      ),
            ),
            (route) => false,
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Something went wrong')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAppleSigningIn = false;
        });
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final initialEmail =
        _isValidEmail(_emailController.text) ? _emailController.text : '';

    await showDialog(
      context: context,
      barrierColor: AppColors.of(context).scrim,
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
    return AuthBackground(
      dimHero: true,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;

        return LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.gap32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: AppSpacing.gap40),
                      // Header Icon
                      Container(
                        width: 64, // h-16
                        height: 64, // w-16
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.rInset,
                          ), // rounded-2xl
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withValues(
                                alpha: 0.25,
                              ), // shadow-2xl equivalent approx
                              blurRadius: 25,
                              offset: const Offset(0, 25),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.menu_book,
                          color: colorScheme.onPrimary,
                          size: 36,
                        ), // text-4xl
                      ),
                      const SizedBox(
                        height: 24,
                      ), // mb-10 in HTML, but here we stack elements
                      // Title
                      Text(
                        'Welcome back',
                        textAlign: TextAlign.center,
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.gap8),

                      // Subtitle
                      Container(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: Text(
                          'Join your circle in daily Scripture reading',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.gap40), // mb-10
                      // Form
                      Form(
                        key: _formKey,
                        child: AutofillGroup(
                          child: Column(
                            children: [
                              // Email
                              _buildStyledInput(
                                context: context,
                                controller: _emailController,
                                label: 'Email',
                                key: const Key('loginEmailField'),
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                textInputAction: TextInputAction.next,
                                autofocus: true,
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return 'Please fill in all fields';
                                  }
                                  if (!_isValidEmail(val.trim())) {
                                    return 'Please enter a valid email address';
                                  }
                                  return null;
                                },
                                suffixIcon:
                                    ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _emailController,
                                  builder: (context, value, child) {
                                    return value.text.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear),
                                            tooltip: 'Clear',
                                            onPressed: () {
                                              _emailController.clear();
                                            },
                                          )
                                        : const SizedBox.shrink();
                                  },
                                ),
                              ),
                              const SizedBox(height: AppSpacing.gap16), // gap-4
                              // Password
                              _buildStyledInput(
                                context: context,
                                controller: _passwordController,
                                label: 'Password',
                                key: const Key('loginPasswordField'),
                                obscureText: !_isPasswordVisible,
                                autofillHints: [AutofillHints.password],
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _submit(),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please fill in all fields';
                                  }
                                  return null;
                                },
                                suffixIcon: IconButton(
                                  tooltip: _isPasswordVisible
                                      ? 'Hide password'
                                      : 'Show password',
                                  icon: Icon(
                                    _isPasswordVisible
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: colorScheme.onSurfaceVariant,
                                    size: 20, // text-xl
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isPasswordVisible = !_isPasswordVisible;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Forgot Password
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: AppSpacing.gap12,
                          ), // -mt-1 in HTML but cleaner here
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
                                  borderRadius:
                                      BorderRadius.circular(AppSpacing.rSmall),
                                  onTap: () {
                                    unawaited(
                                      widget.vibrationService.lightImpact(),
                                    );
                                    _handleForgotPassword();
                                  },
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.all(AppSpacing.gap8),
                                    child: Text(
                                      'Forgot password?',
                                      style: textTheme.bodyMedium?.copyWith(
                                        fontWeight:
                                            FontWeight.w600, // font-semibold
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.gap16),

                      // Login Button
                      SizedBox(
                        height: 56, // h-14
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _submit,
                          child: _loading
                              ? SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    // token-exempt: button submitting
                                    strokeWidth: 2,
                                    color: colorScheme.onPrimary,
                                  ),
                                )
                              : Text(
                                  'Log in',
                                  style: textTheme.labelLarge?.copyWith(
                                    color: colorScheme.onPrimary,
                                    fontWeight: FontWeight.w700, // font-bold
                                    letterSpacing: 0.5, // tracking-wide
                                  ),
                                ),
                        ),
                      ),

                      // OR Divider
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.gap24),
                        child: Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.1,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.gap16,
                              ),
                              child: Text(
                                'OR',
                                style: textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  letterSpacing: 1.5, // tracking-widest
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (widget.appleSignInService.isSupported) ...[
                        AppleSignInButton(
                          service: widget.appleSignInService,
                          onPressed: _handleAppleSignIn,
                        ),
                        const SizedBox(height: AppSpacing.gap12),
                      ],

                      // Continue with Google Button
                      SizedBox(
                        height: 56, // h-14
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _handleGoogleSignIn,
                          child: _isGoogleSigningIn
                              ? SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    // token-exempt: button submitting
                                    strokeWidth: 2,
                                    color: colorScheme.onSurface,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Google Icon
                                    FaIcon(
                                      FontAwesomeIcons.google,
                                      size: 20,
                                      color: colorScheme.onSurface,
                                    ),
                                    const SizedBox(width: AppSpacing.gap12),
                                    Text(
                                      'Continue with Google',
                                      style: textTheme.labelLarge?.copyWith(
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.gap40),

                      // Sign up link
                      Padding(
                        padding: const EdgeInsets.only(
                            bottom: AppSpacing.gap40, top: AppSpacing.gap20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Don't have an account? ",
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500, // font-medium
                                color: colorScheme.onSurfaceVariant,
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
                                    borderRadius: BorderRadius.circular(
                                        AppSpacing.rSmall),
                                    onTap: () {
                                      unawaited(
                                        widget.vibrationService.lightImpact(),
                                      );
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
                                      padding:
                                          const EdgeInsets.all(AppSpacing.gap4),
                                      child: Text(
                                        'Sign up',
                                        style: textTheme.bodyMedium?.copyWith(
                                          fontWeight:
                                              FontWeight.w700, // font-bold
                                          color: colorScheme.primary,
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
        );
      },
    );
  }

  Widget _buildStyledInput({
    required BuildContext context,
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
    String? Function(String?)? validator,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return TextFormField(
      key: key,
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      autofocus: autofocus,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: suffixIcon,
      ),
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
            'Enter your email address to receive a password reset link.',
          ),
          const SizedBox(height: AppSpacing.gap16),
          TextField(
            key: const Key('forgotPasswordEmailField'),
            controller: _controller,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              labelText: 'Email',
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, child) {
                  return value.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Clear email',
                          onPressed: () {
                            _controller.clear();
                          },
                        )
                      : const SizedBox.shrink();
                },
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: _sending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
// token-exempt: button submitting
                    strokeWidth: 2,
                  ),
                )
              : const Text('Send Link'),
        ),
      ],
    );
  }

  Future<void> _send() async {
    final email = _controller.text.trim();
    if (email.isEmpty ||
        !RegExp(
          r"^[a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9-]+\.[a-zA-Z]+$",
        ).hasMatch(email)) {
      unawaited(widget.vibrationService.heavyImpact());
      ScaffoldMessenger.of(context).clearSnackBars();
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
        ScaffoldMessenger.of(context).clearSnackBars();
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
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send reset email. Please try again.'),
          ),
        );
        setState(() {
          _sending = false;
        });
      }
    }
  }
}
