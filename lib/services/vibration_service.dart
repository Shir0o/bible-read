import 'package:vibration/vibration.dart';

import 'error_logger.dart';

/// Provides simple haptic feedback helpers.
class VibrationService {
  /// Creates a [VibrationService].
  const VibrationService();

  /// Trigger a light impact vibration.
  Future<void> lightImpact() => _vibrate(20);

  /// Trigger a medium impact vibration.
  Future<void> mediumImpact() => _vibrate(40);

  /// Trigger a heavy impact vibration.
  Future<void> heavyImpact() => _vibrate(80);

  Future<void> _vibrate(int duration) async {
    try {
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(duration: duration);
      }
    } catch (e, st) {
      await ErrorLogger.log(e, st);
    }
  }
}
