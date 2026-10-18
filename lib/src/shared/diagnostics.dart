import 'package:flutter/foundation.dart';

/// Safe diagnostics: log event names and exception types, never personal data.
abstract final class Diagnostics {
  static void event(String name) {
    if (kDebugMode) debugPrint('[mizan] $name');
  }

  static void failure(String operation, Object error) {
    if (kDebugMode) {
      debugPrint('[mizan] $operation failed (${error.runtimeType})');
    }
  }
}
