import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Logs errors to Firebase Crashlytics.
class ErrorLogger {
  ErrorLogger._();

  /// Crashlytics instance used by [log].
  ///
  /// This is exposed for testing so a mock can be injected. The instance is
  /// created lazily so tests that do not initialise Firebase can still import
  /// this file without throwing a `[core/no-app]` exception.
  @visibleForTesting
  static FirebaseCrashlytics? crashlytics;

  /// Whether to silence all logs. Useful for preventing side effects in tests.
  @visibleForTesting
  static bool muteForTest = false;

  static FirebaseCrashlytics _ensureCrashlytics() =>
      crashlytics ??= FirebaseCrashlytics.instance;

  /// Records [error] and optional [stack] to Crashlytics.
  static Future<void> log(Object error, [StackTrace? stack]) async {
    if (muteForTest) return;

    final errorString = error.toString();

    // Filter out network-related noise that doesn't represent app bugs.
    if (errorString.contains('Failed to load font') ||
        errorString.contains('HTTP request failed, statusCode: 504') ||
        errorString.contains('HandshakeException') ||
        errorString.contains('SocketException')) {
      if (kDebugMode) {
        debugPrint('ErrorLogger (Filtered): $error');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint('ErrorLogger: $error\n$stack');
    }

    // In tests, we want to avoid side effects from uninitialized Firebase apps.
    try {
      if (Firebase.apps.isEmpty && crashlytics == null) return;

      final instance = _ensureCrashlytics();
      await instance.recordError(error, stack, fatal: false);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ErrorLogger failed to record error: $e');
      }
    }
  }

  /// Resets the internal state for testing.
  @visibleForTesting
  static void resetForTest() {
    crashlytics = null;
    muteForTest = false;
  }
}
