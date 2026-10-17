import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

import 'skeleton.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/navigation_menu_scope.dart';

class ProfileSummaryCard extends StatelessWidget {
  final FirebaseAuth auth;
  final VibrationService vibrationService;

  const ProfileSummaryCard({
    super.key,
    required this.auth,
    this.vibrationService = const VibrationService(),
  });

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: GestureDetector(
          onTap: () {
            unawaited(vibrationService.lightImpact());
            NavigationMenuScope.maybeOf(context)?.showMenu(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.surfaceContainerHighest,
                  border: Border.all(
                    color: colorScheme.surfaceContainerHigh,
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: user?.photoURL != null
                      ? CachedNetworkImage(
                          imageUrl: user!.photoURL!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => const Skeleton(
                            width: 64,
                            height: 64,
                            shape: CircleBorder(),
                          ),
                          errorWidget: (context, url, error) => Icon(
                            Icons.person_outline,
                            size: 32,
                            color: colorScheme.outline,
                          ),
                        )
                      : Icon(
                          Icons.person_outline,
                          size: 32,
                          color: colorScheme.outline,
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // Name
              Text(
                user?.displayName ?? 'Reader',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // "View Profile" Affordance (Subtle)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppSpacing.rPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View Profile',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: colorScheme.primary.withValues(alpha: 0.8),
                          ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: colorScheme.primary.withValues(alpha: 0.8),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
