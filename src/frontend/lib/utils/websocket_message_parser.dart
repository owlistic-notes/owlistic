import 'dart:convert';
import '../utils/logger.dart';

/// A class representing the structure of WebSocket messages
class WebSocketMessage {
  final String type;
  final String event;
  final WebSocketPayload? payload;

  const WebSocketMessage({
    required this.type,
    required this.event,
    this.payload,
  });

  /// Parse a raw WebSocket message into a structured object
  factory WebSocketMessage.fromJson(Map<String, dynamic> json) {
    return WebSocketMessage(
      type: json['type'] ?? 'unknown',
      event: json['event'] ?? json['type'] ?? 'unknown',
      payload: json['payload'] != null 
          ? WebSocketPayload.fromJson(json['payload']) 
          : null,
    );
  }

  /// Factory method to parse from a string
  factory WebSocketMessage.fromString(String rawMessage) {
    try {
      final json = jsonDecode(rawMessage);
      return WebSocketMessage.fromJson(json);
    } catch (e) {
      debugPrint('Error parsing WebSocket message: $e');
      return const WebSocketMessage(type: 'error', event: 'parse_error');
    }
  }

  /// Check if this message contains data for a specific model type
  bool hasModelData(String modelType) {
    return WebSocketModelExtractor.hasModelData(this, modelType);
  }
  
  /// Get the ID for a specific model type
  String? getModelId(String modelType) {
    return WebSocketModelExtractor.getModelId(this, modelType);
  }
  
  /// Debug representation
  @override
  String toString() => 'WebSocketMessage{type: $type, event: $event, hasPayload: ${payload != null}}';
}

/// A class representing the structure of the message payload
class WebSocketPayload {
  final dynamic id;
  final dynamic timestamp;
  final dynamic type;
  final WebSocketInnerPayload? innerPayload;

  const WebSocketPayload({
    this.id,
    this.timestamp,
    this.type,
    this.innerPayload,
  });

  /// Get data after proper unwrapping of potentially nested payloads
  Map<String, dynamic>? get data => innerPayload?.data;

  factory WebSocketPayload.fromJson(Map<String, dynamic> json) {
    // Handle the nested payload structure
    return WebSocketPayload(
      id: json['id'],
      timestamp: json['timestamp'],
      type: json['type'],
      innerPayload: json['payload'] != null 
          ? WebSocketInnerPayload.fromJson(json['payload'])
          : (json['data'] != null
              ? WebSocketInnerPayload(data: json['data'])
              : null),
    );
  }
}

/// A class representing the inner payload structure (payload.payload)
class WebSocketInnerPayload {
  final Map<String, dynamic>? data;
  final dynamic eventId;
  final dynamic timestamp;
  final dynamic type;

  const WebSocketInnerPayload({
    this.data,
    this.eventId,
    this.timestamp,
    this.type,
  });

  factory WebSocketInnerPayload.fromJson(Map<String, dynamic> json) {
    return WebSocketInnerPayload(
      data: json['data'],
      eventId: json['event_id'],
      timestamp: json['timestamp'],
      type: json['type'],
    );
  }
}

/// Class to extract specific model data from WebSocket messages
class WebSocketModelExtractor {
  /// Extract raw data from a message at any level of nesting
  static Map<String, dynamic>? extractData(WebSocketMessage message) {
    // First try to get data from payload.data
    if (message.payload?.data != null) {
      return message.payload!.data;
    }
    
    // Then try to get data from payload.innerPayload.data
    if (message.payload?.innerPayload?.data != null) {
      return message.payload!.innerPayload!.data;
    }
    
    // No data found
    return null;
  }
  
  /// Check if message contains data for a specific model type
  static bool hasModelData(WebSocketMessage message, String modelType) {
    final data = extractData(message);
    if (data == null) return false;
    
    switch (modelType) {
      case 'note':
        return data.containsKey('note_id');
      case 'notebook':
        return data.containsKey('notebook_id');
      case 'block':
        return data.containsKey('block_id');
      case 'task':
        return data.containsKey('task_id');
      default:
        return false;
    }
  }
  
  /// Get model ID using generic extraction
  static String? getModelId(WebSocketMessage message, String modelType) {
    final idField = '${modelType}_id';
    return extractId(message, idField);
  }
  
  /// Extract a specific ID from the message data
  static String? extractId(WebSocketMessage message, String idField) {
    // Get data from any level
    final data = extractData(message);
    if (data == null) return null;
    
    // Look for the specific ID field
    if (data.containsKey(idField)) {
      return data[idField]?.toString();
    }
    
    // Try with just 'id' if the specific field wasn't found
    if (idField != 'id' && data.containsKey('id')) {
      return data['id']?.toString();
    }
    
    return null;
  }

  // Resource-specific extraction methods
  static Map<String, dynamic>? extractNoteData(WebSocketMessage message) => extractData(message);
  static String? extractNoteId(WebSocketMessage message) => extractId(message, 'note_id');
  static Map<String, dynamic>? extractNotebookData(WebSocketMessage message) => extractData(message);
  static String? extractNotebookId(WebSocketMessage message) => extractId(message, 'notebook_id');
  static Map<String, dynamic>? extractBlockData(WebSocketMessage message) => extractData(message);
  static String? extractBlockId(WebSocketMessage message) => extractId(message, 'block_id');
  static Map<String, dynamic>? extractTaskData(WebSocketMessage message) => extractData(message);
  static String? extractTaskId(WebSocketMessage message) => extractId(message, 'task_id');
}

// Helper for logging outside of Flutter context
void debugPrint(String message) {
  final logger = Logger('WebSocketParser');
  logger.debug(message);
}
