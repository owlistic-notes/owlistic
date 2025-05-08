import 'package:flutter/material.dart';
import '../models/block.dart';
import '../models/note.dart';
import '../utils/logger.dart';

/// DataConverter provides utility methods for converting between different data formats
/// throughout the application to ensure consistency and reduce code duplication.
class DataConverter {
  static final Logger _logger = Logger('DataConverter');

  /// Convert dynamic JSON content to a standardized Map format
  /// Ensures consistent content structure regardless of input format
  static Map<String, dynamic> normalizeContent(dynamic content) {
    try {
      if (content is Map) {
        // Create a new map to avoid modifying the original
        final result = Map<String, dynamic>.from(content);
        
        // Ensure text field exists
        if (!result.containsKey('text')) {
          result['text'] = '';
        }
        
        // Normalize spans if present
        if (result.containsKey('spans') && result['spans'] is List) {
          final spans = result['spans'] as List;
          result['spans'] = spans.map((span) {
            if (span is Map) return Map<String, dynamic>.from(span);
            return <String, dynamic>{};
          }).toList();
        }
        
        _logger.debug('Normalized content: $result');
        return result;
      } else if (content is String) {
        // Convert legacy string content to the new format
        return {'text': content};
      } else if (content == null) {
        return {'text': ''};
      }
      
      // If we can't determine the type, convert to string and wrap
      return {'text': content.toString()};
    } catch (e) {
      _logger.error('Error normalizing content', e);
      return {'text': ''};
    }
  }

  /// Extract text content from a content object (either Map or String)
  static String extractTextContent(dynamic content) {
    try {
      if (content is String) {
        return content;
      } else if (content is Map) {
        return content['text']?.toString() ?? '';
      }
      return '';
    } catch (e) {
      _logger.error('Error extracting text content', e);
      return '';
    }
  }

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

  /// Extract formatting spans from rich text content
  static List<Map<String, dynamic>>? extractSpans(dynamic content) {
    final Map<String, dynamic> contentMap = normalizeContent(content);
    if (contentMap.containsKey('spans')) {
      final spans = contentMap['spans'];
      if (spans is List) {
        return List<Map<String, dynamic>>.from(spans.map((span) {
          if (span is Map) return Map<String, dynamic>.from(span);
          return <String, dynamic>{};
        }));
      }
    }
    return null;
  }
  
  /// Create a color from a hex string (e.g., "#FF0000")
  static Color? colorFromHex(String? hexString) {
    if (hexString == null || hexString.isEmpty) {
      return null;
    }
    
    hexString = hexString.toUpperCase().replaceAll('#', '');
    if (hexString.length == 6) {
      hexString = 'FF$hexString';
    }
    
    try {
      return Color(int.parse(hexString, radix: 16));
    } catch (e) {
      _logger.error('Error parsing color from hex: $hexString', e);
      return null;
    }
  }
  
  /// Format byte size to human-readable string (e.g., "1.5 MB")
  static String formatByteSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      final kb = bytes / 1024;
      return '${kb.toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return '${mb.toStringAsFixed(1)} MB';
    } else {
      final gb = bytes / (1024 * 1024 * 1024);
      return '${gb.toStringAsFixed(1)} GB';
    }
  }
  
  /// Get summarized text for display in UI (limited length with ellipsis)
  static String getSummaryText(String text, {int maxLength = 100}) {
    if (text.length <= maxLength) {
      return text;
    }
    
    return '${text.substring(0, maxLength)}...';
  }
  
  /// Extract block content based on block type for consistent display
  static Map<String, dynamic> getBlockContent(Block block) {
    final Map<String, dynamic> contentMap = normalizeContent(block.content);
    
    switch (block.type) {
      case 'heading':
        return {
          'text': contentMap['text'] ?? '',
          'level': parseIntSafely(contentMap['level'], defaultValue: 1),
          'spans': contentMap['spans'] ?? [],
        };
      
      case 'task':
        return {
          'text': contentMap['text'] ?? '',
          'is_completed': contentMap['is_completed'],
          'spans': contentMap['spans'] ?? [],
        };
        
      case 'code':
        return {
          'text': contentMap['text'] ?? '',
          'language': contentMap['language'] ?? 'plain',
        };
        
      default:
        return {
          'text': contentMap['text'] ?? '',
          'spans': contentMap['spans'] ?? [],
        };
    }
  }
  
  /// Get summary of a note based on its blocks
  static String getNoteSummary(Note note, {int maxLength = 100}) {
    if (note.blocks.isEmpty) {
      return '';
    }
    
    // Get text from the first block
    final String text = extractTextContent(note.blocks.first.content);
    return getSummaryText(text, maxLength: maxLength);
  }
}
