import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart' as logging;

/// Log levels for the application
enum LogLevel {
  debug,   // Only shown in debug mode
  info,    // Normal flow information
  warning, // Potential issues
  error,   // Errors that don't crash the app
}

/// A simple logging utility that wraps package:logging/logging.dart
class Logger {
  late logging.Logger _internalLogger;
  
  /// The tag identifies the source of the log
  final String tag;
  
  /// Track whether the logging system has been initialized
  static bool _initialized = false;
  
  /// Create a logger for a specific component
  Logger(this.tag) {
    _ensureInitialized();
    _internalLogger = logging.Logger(tag);
  }
  
  /// Initialize the logging framework once
  static void _ensureInitialized() {
    if (!_initialized) {
      logging.hierarchicalLoggingEnabled = true;
      
      logging.Logger.root.level = kDebugMode 
          ? logging.Level.ALL 
          : logging.Level.INFO;
      
      logging.Logger.root.onRecord.listen((record) {
        final timestamp = _formatTimestamp(record.time);
        final level = record.level.name.padRight(5).substring(0, 5);
        final message = record.message;
        final loggerName = record.loggerName;
        
        print("$timestamp | $level | $loggerName | $message");
        
        if (record.error != null) {
          print("$timestamp | $level | $loggerName | ↳ ${record.error}");
          
          if (record.stackTrace != null && kDebugMode) {
            print("$timestamp | $level | $loggerName | ↳ ${record.stackTrace}");
          }
        }
      });
      
      _initialized = true;
    }
  }
  
  /// Format timestamp to consistent output
  static String _formatTimestamp(DateTime time) {
    return "${time.year}-${_pad(time.month)}-${_pad(time.day)} "
           "${_pad(time.hour)}:${_pad(time.minute)}:${_pad(time.second)}"
           ".${_pad(time.millisecond, 3)}";
  }
  
  /// Pad a number with leading zeros
  static String _pad(int n, [int width = 2]) {
    return n.toString().padLeft(width, '0');
  }
  
  /// Log a debug message (only shown in debug mode)
  void debug(String message) {
    _internalLogger.fine(message);
  }
  
  /// Log an info message
  void info(String message) {
    _internalLogger.info(message);
  }
  
  /// Log a warning message
  void warning(String message) {
    _internalLogger.warning(message);
  }
  
  /// Log an error message
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _internalLogger.severe(message, error, stackTrace);
  }
  
  /// Static method to get a logger for a class
  static Logger forClass(Type type) {
    return Logger(type.toString());
  }
}

/// Global logger for general use
final Logger log = Logger('Global');
