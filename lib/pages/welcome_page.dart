import 'package:flutter/material.dart';

import '../widgets/auth/auth_background.dart';

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
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: textTheme.displaySmall?.copyWith(
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
              const SizedBox(height: 16),

              // Description
              Text(
                'Experience the Bible in community. Create shared schedules, discuss insights, and keep your friends accountable every day.',
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),

              // Get Started Button
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: onGetStarted,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                    elevation: 4,
                    shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28), // rounded-full
                    ),
                  ),
                  child: Text(
                    'Get Started',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // I already have an account Button
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: onLogin,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                      width: 1,
                    ),
                    backgroundColor: colorScheme.surface.withValues(alpha: 0),
                    foregroundColor: colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: Text(
                    'I already have an account',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}
