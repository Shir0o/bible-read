import 'dart:async';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/signup_page.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:bible_read/services/google_sign_in_factory.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/theme/app_theme.dart';
import 'package:bible_read/widgets/animated_page_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  final VibrationService vibrationService;
  final BaseCacheManager? cacheManager;
  final Widget Function(BuildContext)? mainPageBuilder;

  LoginPage({
    super.key,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn Function()? googleSignInProvider,
    VibrationService? vibrationService,
    this.cacheManager,
    this.mainPageBuilder,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        googleSignInProvider = googleSignInProvider ?? createGoogleSignIn,
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
          const SnackBar(
            content: Text('Please fill in all fields'),
          ),
        );
      } else if (!_isValidEmail(email)) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid email address'),
          ),
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

      await widget.auth.signInWithCredential(credential);

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: widget.mainPageBuilder ?? (_) => MainPage(),
          ),
          (route) => false,
        );
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
    const authColorScheme = AppTheme.designDarkScheme;

    return Theme(
      data: AppTheme.appTheme(authColorScheme),
      child: Builder(
        builder: (context) {
          final colorScheme = Theme.of(context).colorScheme;
          final textTheme = Theme.of(context).textTheme;

          return Scaffold(
            backgroundColor: colorScheme.surface,
            body: Stack(
              children: [
                // Background Image
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl:
                        'https://lh3.googleusercontent.com/aida-public/AB6AXuCfzrtAkMN22RwB2ZiqvZ7-a-u3c-1Q3SYe1V6xrgX8oGAGl0fcdKTFGezJhbpHXu8o1n3ePffi_ZF79ajNqZfUsXddI-13tqUsvWaaiNgLKefDYXK0KgRmpDPKA_meuN2OR1SNZqMAEjz6CXvzG7W7A6V3Do9bc_HOxoFH-5RLqbVZek6jTgqM-ERrpHdie1ASqWaBbJxXCKiQDVcL0TkaFmAp07o9oaHvgLprritLLT8kmwNubpE4Xl6s2ETlB0C7b6HWAgBESSe6',
                    fit: BoxFit.cover,
                    cacheManager: widget.cacheManager,
                    placeholder: (context, url) =>
                        Container(color: colorScheme.surface),
                    errorWidget: (context, url, error) =>
                        Container(color: colorScheme.surface),
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
                          colorScheme.surface,
                          colorScheme.surface.withValues(alpha: 0.9),
                          colorScheme.surface.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                // Black Overlay
                Positioned.fill(
                  child: Container(
                    color: colorScheme.scrim.withValues(alpha: 0.4),
                  ),
                ),

                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32.0,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(height: 40),
                                // Header Icon
                                Container(
                                  width: 64, // h-16
                                  height: 64, // w-16
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    borderRadius: BorderRadius.circular(
                                      16,
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
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // Subtitle
                                Container(
                                  constraints: const BoxConstraints(
                                    maxWidth: 280,
                                  ),
                                  child: Text(
                                    'Join your community in daily Scripture reading',
                                    textAlign: TextAlign.center,
                                    style: textTheme.bodyLarge?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 40), // mb-10
                                // Form
                                Form(
                                  key: _formKey,
                                  child: AutofillGroup(
                                    child: Column(
                                      children: [
                                        // Email or Username
                                        _buildStyledInput(
                                          context: context,
                                          controller: _emailController,
                                          label: 'Email or Username',
                                          key: const Key('loginEmailField'),
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          autofillHints: const [
                                            AutofillHints.email,
                                          ],
                                          textInputAction: TextInputAction.next,
                                          autofocus: true,
                                          validator: (val) {
                                            if (val == null ||
                                                val.trim().isEmpty) {
                                              return 'Please fill in all fields';
                                            }
                                            if (!_isValidEmail(val.trim())) {
                                              return 'Please enter a valid email address';
                                            }
                                            return null;
                                          },
                                          suffixIcon: ValueListenableBuilder<
                                              TextEditingValue>(
                                            valueListenable: _emailController,
                                            builder: (context, value, child) {
                                              return value.text.isNotEmpty
                                                  ? IconButton(
                                                      icon: const Icon(
                                                        Icons.clear,
                                                      ),
                                                      tooltip: 'Clear',
                                                      onPressed: () {
                                                        _emailController
                                                            .clear();
                                                      },
                                                    )
                                                  : const SizedBox.shrink();
                                            },
                                          ),
                                        ),
                                        const SizedBox(height: 16), // gap-4
                                        // Password
                                        _buildStyledInput(
                                          context: context,
                                          controller: _passwordController,
                                          label: 'Password',
                                          key: const Key('loginPasswordField'),
                                          obscureText: !_isPasswordVisible,
                                          autofillHints: [
                                            AutofillHints.password,
                                          ],
                                          textInputAction: TextInputAction.done,
                                          onSubmitted: (_) => _submit(),
                                          validator: (value) {
                                            if (value == null ||
                                                value.isEmpty) {
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
                                              color:
                                                  colorScheme.onSurfaceVariant,
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
                                ),

                                // Forgot Password
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      top: 12.0,
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
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            onTap: () {
                                              unawaited(
                                                widget.vibrationService
                                                    .lightImpact(),
                                              );
                                              _handleForgotPassword();
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                8.0,
                                              ),
                                              child: Text(
                                                'Forgot Password?',
                                                style: textTheme.bodyMedium
                                                    ?.copyWith(
                                                  fontWeight: FontWeight
                                                      .w600, // font-semibold
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
                                const SizedBox(height: 16),

                                // Login Button
                                SizedBox(
                                  height: 56, // h-14
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: colorScheme.primary,
                                      foregroundColor: colorScheme.onPrimary,
                                      elevation: 10, // shadow-lg
                                      shadowColor: colorScheme.shadow
                                          .withValues(alpha: 0.3),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            AppSpacing.rCard),
                                      ),
                                    ),
                                    child: _loading
                                        ? SizedBox(
                                            height: 24,
                                            width: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: colorScheme.onPrimary,
                                            ),
                                          )
                                        : Text(
                                            'Login',
                                            style:
                                                textTheme.labelLarge?.copyWith(
                                              fontWeight:
                                                  FontWeight.bold, // font-bold
                                              letterSpacing:
                                                  0.5, // tracking-wide
                                            ),
                                          ),
                                  ),
                                ),

                                // OR Divider
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 24.0,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Divider(
                                          color: colorScheme.outlineVariant
                                              .withValues(alpha: 0.1),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        child: Text(
                                          'OR',
                                          style: textTheme.labelSmall?.copyWith(
                                            fontWeight:
                                                FontWeight.bold, // font-bold
                                            color: colorScheme.onSurfaceVariant,
                                            letterSpacing:
                                                1.5, // tracking-widest
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Divider(
                                          color: colorScheme.outlineVariant
                                              .withValues(alpha: 0.1),
                                        ),
                                      ),
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
                                      backgroundColor:
                                          colorScheme.surfaceBright,
                                      foregroundColor: colorScheme.onSurface,
                                      elevation: 4, // shadow-md
                                      shadowColor: colorScheme.shadow
                                          .withValues(alpha: 0.1),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            AppSpacing.rCard),
                                        side: BorderSide(
                                          color: colorScheme.outlineVariant,
                                        ),
                                      ),
                                    ),
                                    child: _isGoogleSigningIn
                                        ? SizedBox(
                                            height: 24,
                                            width: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: colorScheme.onSurface,
                                            ),
                                          )
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              // Google Icon
                                              FaIcon(
                                                FontAwesomeIcons.google,
                                                size: 20,
                                                color: colorScheme.onSurface,
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                'Continue with Google',
                                                style: textTheme.labelLarge
                                                    ?.copyWith(
                                                  fontWeight: FontWeight
                                                      .w600, // font-semibold
                                                  color: colorScheme.onSurface,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),

                                const SizedBox(height: 40),

                                // Sign up link
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: 40.0,
                                    top: 20,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        "Don't have an account? ",
                                        style: textTheme.bodyMedium?.copyWith(
                                          fontWeight:
                                              FontWeight.w500, // font-medium
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
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              onTap: () {
                                                unawaited(
                                                  widget.vibrationService
                                                      .lightImpact(),
                                                );
                                                Navigator.of(context).push(
                                                  animatedPageRoute(
                                                    SignupPage(
                                                      auth: widget.auth,
                                                      firestore:
                                                          widget.firestore,
                                                      vibrationService: widget
                                                          .vibrationService,
                                                      googleSignInProvider: widget
                                                          .googleSignInProvider,
                                                      mainPageBuilder: widget
                                                          .mainPageBuilder,
                                                    ),
                                                  ),
                                                );
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  4.0,
                                                ),
                                                child: Text(
                                                  'Sign up',
                                                  style: textTheme.bodyMedium
                                                      ?.copyWith(
                                                    fontWeight: FontWeight
                                                        .bold, // font-bold
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
                  ),
                ),
              ],
            ),
          );
        },
      ),
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

    const radius = BorderRadius.vertical(top: Radius.circular(12));

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
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: colorScheme.surface.withValues(alpha: 0.08),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          borderRadius: radius,
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
          borderRadius: radius,
        ),
        errorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colorScheme.error, width: 2),
          borderRadius: radius,
        ),
        focusedErrorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colorScheme.error, width: 2),
          borderRadius: radius,
        ),
        contentPadding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
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
          const SizedBox(height: 16),
          TextField(
            key: const Key('forgotPasswordEmailField'),
            controller: _controller,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              labelText: 'Email',
              border: const OutlineInputBorder(),
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
