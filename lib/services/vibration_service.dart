import 'package:firebase_auth/firebase_auth.dart';
import 'package:vibration/vibration.dart';

import 'error_logger.dart';
import 'notification_preferences_service.dart';

/// Provides simple haptic feedback helpers.
class VibrationService {
  /// Firebase auth instance used to identify the current user.
  final FirebaseAuth? auth;

  /// Service used to read vibration preferences.
  final NotificationPreferencesService? prefsService;

  /// Creates a [VibrationService].
  const VibrationService({this.auth, this.prefsService});

  /// Trigger a standard tap vibration.
  Future<void> tap() => lightImpact();

  /// Trigger a light impact vibration.
  Future<void> lightImpact() => _vibrate(20);

  /// Trigger a medium impact vibration.
  Future<void> mediumImpact() => _vibrate(40);

  /// Trigger a heavy impact vibration.
  Future<void> heavyImpact() => _vibrate(80);

  Future<void> _vibrate(int duration) async {
    try {
      FirebaseAuth? authInstance;
      try {
        authInstance = auth ?? FirebaseAuth.instance;
      } catch (e) {
        // Fallback for tests or apps without Firebase initialization
        if (await Vibration.hasVibrator()) {
          await Vibration.vibrate(duration: duration);
        }
        return;
      }

      final user = authInstance.currentUser;
      if (user == null) {
        // If no user is logged in, we default to enabled for anonymous vibration feedback
        // or we could just skip. Let's vibrate anyway for basic UX.
        if (await Vibration.hasVibrator()) {
          await Vibration.vibrate(duration: duration);
        }
        return;
      }

      final enabled = await (prefsService ?? NotificationPreferencesService())
          .fetchVibrationEnabled(user.uid);
      if (!enabled) return;
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(duration: duration);
      }
    } catch (e, st) {
      // In tests, we might not have a logger correctly initialized either
      try {
        await ErrorLogger.log(e, st);
      } catch (_) {}
    }
  }
}
