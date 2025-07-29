import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Logs errors to Firebase Crashlytics.
class ErrorLogger {
  ErrorLogger._();

  /// Records [error] and optional [stack] to Crashlytics.
  static Future<void> log(Object error, [StackTrace? stack]) async {
    if (kDebugMode) {
      debugPrint('$error\n$stack');
    }
    try {
      await FirebaseCrashlytics.instance
          .recordError(error, stack, fatal: false);
    } catch (_) {
      // ignore errors if Crashlytics is unavailable
    }
  }
}
