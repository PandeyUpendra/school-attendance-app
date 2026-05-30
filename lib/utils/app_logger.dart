import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kDebugMode;

/// Debug-only logging wrapper. In release builds (`kDebugMode == false`) every
/// method is a no-op, so log strings are eligible for tree-shaking and never
/// reach the Play Store binary's runtime output. In debug, messages are routed
/// through `dart:developer.log` so they show up with proper tagging in the
/// Flutter DevTools logging view (instead of stdout `print` noise).
class AppLogger {
  AppLogger._();

  static void d(String tag, String message) {
    if (kDebugMode) {
      developer.log(message, name: tag);
    }
  }

  static void e(String tag, String message, [Object? error, StackTrace? stack]) {
    if (kDebugMode) {
      developer.log(message, name: tag, error: error, stackTrace: stack);
    }
  }
}
