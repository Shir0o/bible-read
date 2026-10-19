import 'dart:async';

import 'package:flutter/material.dart';

import '../services/error_logger.dart';
import '../services/friend_service.dart';

/// Redeems [code] for the add-a-friend screens and handles the shared
/// outcomes: on [FriendRedemption.added] it confirms with a SnackBar and
/// closes the screen; on a failed call it logs and says so. Returns the
/// outcome, or null when the call failed, so the screen only renders the
/// self, already-Friends and unknown cases its own way.
Future<FriendRedemption?> redeemFriendCode(
  BuildContext context, {
  required FriendService friendService,
  required String code,
  required String displayName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    final result = await friendService.redeem(code);
    if (result == FriendRedemption.added) {
      messenger.showSnackBar(
        SnackBar(content: Text('You’re now friends with $displayName')),
      );
      unawaited(navigator.maybePop());
    }
    return result;
  } catch (e, st) {
    unawaited(ErrorLogger.log(e, st));
    messenger.showSnackBar(
      const SnackBar(content: Text('Something went wrong. Try again.')),
    );
    return null;
  }
}
