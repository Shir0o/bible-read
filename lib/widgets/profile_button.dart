import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import '../services/vibration_service.dart';
import '../widgets/navigation_menu_scope.dart';

class ProfileButton extends StatelessWidget {
  final FirebaseAuth auth;
  final VibrationService vibrationService;

  const ProfileButton({
    super.key,
    required this.auth,
    this.vibrationService = const VibrationService(),
  });

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    return GestureDetector(
      onTap: () {
        unawaited(vibrationService.lightImpact());
        NavigationMenuScope.maybeOf(context)?.showMenu(context);
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 16.0),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          child: user?.photoURL != null
              ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: user!.photoURL!,
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    errorWidget: (context, url, error) => Icon(
                      Icons.person,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Icon(
                  Icons.person,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
        ),
      ),
    );
  }
}
