import 'package:owlistic/utils/logger.dart';

/// DataConverter provides utility methods for converting between different data formats
/// throughout the application to ensure consistency and reduce code duplication.
class DataConverter {
  static final Logger _logger = Logger('DataConverter');

  /// Format date for display in the UI
  static String formatDate(DateTime? date, {bool includeTime = false}) {
    if (date == null) {
      return '';
    }
    
    final dateString = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    if (!includeTime) {
      return dateString;
    }
    
    final timeString = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return '$dateString $timeString';
  }

  /// Get relative time (e.g., "5 minutes ago") for display in the UI
  static String getRelativeTime(DateTime? date) {
    if (date == null) {
      return '';
    }
    
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inDays < 30) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else {
      return formatDate(date);
    }
  }

  /// Handle numeric values in JSON that might be strings or numbers
  static int parseIntSafely(dynamic value, {int defaultValue = 0}) {
    try {
      if (value == null) {
        return defaultValue;
      } else if (value is int) {
        return value;
      } else if (value is String) {
        return int.tryParse(value) ?? defaultValue;
      } else {
        return defaultValue;
      }
    } catch (e) {
      _logger.error('Error parsing int value', e);
      return defaultValue;
    }
  }
  
  /// Parse a double value safely from various input types
  static double parseDoubleSafely(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    
    if (value is double) return value;
    
    if (value is int) return value.toDouble();
    
    if (value is String) {
      try {
        return double.parse(value);
      } catch (e) {
        return defaultValue;
      }
    }
    
    return defaultValue;
  }
}
