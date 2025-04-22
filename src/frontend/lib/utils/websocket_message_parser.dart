import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/logger.dart';

/// Class to represent a standardized WebSocket message with RBAC information
class WebSocketMessage {
  final String type;
  final String event;
  final Map<String, dynamic> payload;
  final String? resourceType;
  final String? resourceId;

  WebSocketMessage({
    required this.type,
    required this.event,
    required this.payload,
    this.resourceType,
    this.resourceId,
  });

  factory WebSocketMessage.fromJson(Map<String, dynamic> json) {
    // Get standard fields directly from the message
    return WebSocketMessage(
      type: json['type'] ?? 'unknown',
      event: json['event'] ?? 'unknown',
      payload: json['payload'] != null 
          ? Map<String, dynamic>.from(json['payload']) 
          : {},
      resourceType: json['resource_type'],
      resourceId: json['resource_id'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'event': event,
      'payload': payload,
      if (resourceType != null) 'resource_type': resourceType,
      if (resourceId != null) 'resource_id': resourceId,
    };
  }
}

/// Helper class for extracting entity IDs from WebSocket messages
class WebSocketModelExtractor {
  /// Extract note ID from message payload
  static String? extractNoteId(WebSocketMessage message) {
    // First check if resourceId is already set and resource type is note
    if (message.resourceType == 'note' && message.resourceId != null) {
      return message.resourceId;
    }
    
    final payload = message.payload;
    
    // Check direct payload fields
    if (payload.containsKey('note_id')) {
      return payload['note_id']?.toString();
    }
    
    // Check in data structure if present
    if (payload.containsKey('data')) {
      final data = payload['data'];
      if (data is Map) {
        return data['note_id']?.toString() ?? 
               data['id']?.toString();
      }
    }
    
    return null;
  }

  /// Extract notebook ID from message payload
  static String? extractNotebookId(WebSocketMessage message) {
    // First check if resourceId is already set and resource type is notebook
    if (message.resourceType == 'notebook' && message.resourceId != null) {
      return message.resourceId;
    }
    
    final payload = message.payload;
    
    // Check direct payload fields
    if (payload.containsKey('notebook_id')) {
      return payload['notebook_id']?.toString();
    }
    
    // Check in data structure if present
    if (payload.containsKey('data')) {
      final data = payload['data'];
      if (data is Map) {
        return data['notebook_id']?.toString() ?? 
               data['id']?.toString();
      }
    }
    
    return null;
  }

  /// Extract block ID from message payload
  static String? extractBlockId(WebSocketMessage message) {
    // First check if resourceId is already set and resource type is block
    if (message.resourceType == 'block' && message.resourceId != null) {
      return message.resourceId;
    }
    
    final payload = message.payload;
    
    // Check direct payload fields
    if (payload.containsKey('block_id')) {
      return payload['block_id']?.toString();
    }
    
    // Check in data structure if present
    if (payload.containsKey('data')) {
      final data = payload['data'];
      if (data is Map) {
        return data['block_id']?.toString() ?? 
               data['id']?.toString();
      }
    }
    
    return null;
  }
}

/// Simple helper to parse WebSocket messages
class WebSocketParser {
  static final Logger _logger = Logger('WebSocketParser');
  
  /// Parse a raw message into a WebSocketMessage object
  static WebSocketMessage? parse(dynamic data) {
    try {
      if (data is String) {
        data = jsonDecode(data);
      }
      
      if (data is Map<String, dynamic>) {
        return WebSocketMessage.fromJson(data);
      }
      
      _logger.warning('Received non-map data: $data');
      return null;
    } catch (e) {
      _logger.error('Error parsing WebSocket message: $e');
      if (data is String) {
        _logger.debug('Failed to parse: $data');
      }
      return null;
    }
  }
  
  /// Try to parse multiple messages from a single string
  static List<WebSocketMessage> parseMultiple(String data) {
    List<WebSocketMessage> results = [];
    
    try {
      // Check if it's a JSON array
      var decoded = jsonDecode(data);
      
      if (decoded is List) {
        for (var item in decoded) {
          if (item is Map<String, dynamic>) {
            var message = WebSocketMessage.fromJson(item);
            results.add(message);
          }
        }
      } else if (decoded is Map<String, dynamic>) {
        // Single object
        results.add(WebSocketMessage.fromJson(decoded));
      }
    } catch (e) {
      _logger.error('Error parsing multiple messages: $e');
      
      // Try to split by newlines or JSON object boundaries
      try {
        // Simple splitting by line breaks and curly braces
        List<String> parts = _splitJsonObjects(data);
        
        for (var part in parts) {
          try {
            var partMap = jsonDecode(part);
            if (partMap is Map<String, dynamic>) {
              results.add(WebSocketMessage.fromJson(partMap));
            }
          } catch (e) {
            // Skip invalid parts
            _logger.debug('Skipping invalid JSON part: $part');
          }
        }
      } catch (e) {
        _logger.error('Failed to parse message parts: $e');
      }
    }
    
    return results;
  }
  
  // Helper to split potential multiple JSON objects
  static List<String> _splitJsonObjects(String text) {
    List<String> results = [];
    
    // Most basic implementation - look for complete JSON objects
    int start = text.indexOf('{');
    while (start >= 0) {
      int depth = 1;
      int end = start + 1;
      
      while (depth > 0 && end < text.length) {
        if (text[end] == '{') depth++;
        else if (text[end] == '}') depth--;
        end++;
      }
      
      if (depth == 0) {
        // Found a complete object
        results.add(text.substring(start, end));
      }
      
      // Look for next object
      start = text.indexOf('{', end);
    }
    
    return results;
  }
}
