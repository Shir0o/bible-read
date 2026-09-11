import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../services/apple_sign_in_service.dart';

/// Standard Apple Sign-In button that adheres to Apple HIG and conditionally
/// hides itself on platforms where Apple Sign-In is unsupported.
class AppleSignInButton extends StatelessWidget {
  final AppleSignInService service;
  final VoidCallback? onPressed;
  final double height;
  final double cornerRadius;

  const AppleSignInButton({
    super.key,
    required this.service,
    required this.onPressed,
    this.height = 56,
    this.cornerRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    if (!service.isSupported) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = isDark
        ? SignInWithAppleButtonStyle.white
        : SignInWithAppleButtonStyle.black;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: SignInWithAppleButton(
        key: const Key('appleSignInButton'),
        onPressed: onPressed,
        style: style,
        borderRadius: BorderRadius.circular(cornerRadius),
        height: height,
      ),
    );
  }
}
