import 'package:flutter/foundation.dart';

/// Simple logger class for consistent logging across the app
class Logger {
  final String _tag;
  
  /// Create a logger with a tag (usually the class name)
  Logger(this._tag);
  
  /// Log an info message
  void info(String message) {
    _log('INFO', message);
  }
  
  /// Log a debug message
  void debug(String message) {
    _log('DEBUG', message);
  }
  
  /// Log a warning message
  void warning(String message) {
    _log('WARNING', message);
  }
  
  /// Log an error message with optional stack trace
  void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _log('ERROR', message);
    if (error != null) {
      _log('ERROR', '  Cause: $error');
    }
    if (stackTrace != null) {
      _log('ERROR', '  Stack: $stackTrace');
    }
  }
  
  /// Internal log method
  void _log(String level, String message) {
    if (kDebugMode) {
      print('[$level] $_tag: $message');
    }
  }
}
