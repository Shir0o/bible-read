import 'package:flutter/material.dart';

/// A Friend's avatar: their photo, or their initial when there is none.
/// Shared by the "Have a code?" preview, the invite screen and the Friend
/// sheet.
class FriendAvatar extends StatelessWidget {
  /// Display name; its first letter is the fallback.
  final String? name;

  /// Profile photo URL, when known.
  final String? photoUrl;

  /// Radius of the circle.
  final double radius;

  /// Creates a [FriendAvatar].
  const FriendAvatar({
    super.key,
    this.name,
    this.photoUrl,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final trimmed = name?.trim() ?? '';
    final initial =
        trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.secondaryContainer,
      foregroundImage: (photoUrl != null && photoUrl!.isNotEmpty)
          ? NetworkImage(photoUrl!)
          : null,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: radius * 0.72,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
