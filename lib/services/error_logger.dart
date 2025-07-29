import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Logs errors to Firebase Crashlytics.
class ErrorLogger {
  ErrorLogger._();

  static final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  /// Records [error] and optional [stack] to Crashlytics.
  static Future<void> log(Object error, [StackTrace? stack]) async {
    if (kDebugMode) {
      debugPrint('$error\n$stack');
    }
    await _crashlytics.recordError(error, stack, fatal: false);
  }
}
