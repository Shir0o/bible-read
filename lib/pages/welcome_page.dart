import 'package:flutter/material.dart';

import '../widgets/auth/auth_background.dart';
import '../theme/app_theme.dart';

class WelcomePage extends StatelessWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onLogin;

  const WelcomePage({
    super.key,
    required this.onGetStarted,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return AuthBackground(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;

        return Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.gap24, vertical: AppSpacing.gap40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
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
                  children: [
                    const TextSpan(text: 'Read Together,\n'),
                    TextSpan(
                      text: 'Grow Together',
                      style: textTheme.displaySmall?.copyWith(
                        color: colorScheme.primary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.gap16),

              // Description
              Text(
                'Experience the Bible together. Create shared schedules, discuss insights, and keep each other accountable every day.',
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.gap40),

              // Get Started Button
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: onGetStarted,
                  child: Text(
                    'Get started',
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.gap16),

              // I already have an account Button
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: onLogin,
                  child: Text(
                    'I already have an account',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.gap24),
            ],
          ),
        );
      },
    );
  }
}
