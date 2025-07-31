import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Logs errors to Firebase Crashlytics.
class ErrorLogger {
  ErrorLogger._();

  /// Crashlytics instance used by [log].
  ///
  /// This is exposed for testing so a mock can be injected.
  @visibleForTesting
  static FirebaseCrashlytics crashlytics = FirebaseCrashlytics.instance;

  /// Records [error] and optional [stack] to Crashlytics.
  static Future<void> log(Object error, [StackTrace? stack]) async {
    if (kDebugMode) {
      debugPrint('$error\n$stack');
    }
    if (Firebase.apps.isEmpty) return;
    try {
      await crashlytics.recordError(error, stack, fatal: false);
    } catch (_) {
      // ignore errors if Crashlytics is unavailable
    }
  }
}
