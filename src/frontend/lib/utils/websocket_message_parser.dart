import 'dart:convert';

/// A class representing the structure of WebSocket messages
class WebSocketMessage {
  final String type;
  final String event;
  final WebSocketPayload? payload;

  WebSocketMessage({
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
      print('Error parsing WebSocket message: $e');
      return WebSocketMessage(type: 'error', event: 'parse_error');
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
  final dynamic id; // Changed from String? to dynamic to handle various ID types
  final dynamic timestamp; // Changed from String? to dynamic
  final dynamic type; // Changed from String? to dynamic
  final WebSocketInnerPayload? innerPayload;

  WebSocketPayload({
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
      id: json['id'], // No toString() conversion here
      timestamp: json['timestamp'], // No toString() conversion here
      type: json['type'], // No toString() conversion here
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
  final dynamic eventId; // Changed from String? to dynamic
  final dynamic timestamp; // Changed from String? to dynamic
  final dynamic type; // Changed from String? to dynamic

  WebSocketInnerPayload({
    this.data,
    this.eventId,
    this.timestamp,
    this.type,
  });

  factory WebSocketInnerPayload.fromJson(Map<String, dynamic> json) {
    return WebSocketInnerPayload(
      data: json['data'],
      eventId: json['event_id'], // No toString() conversion here
      timestamp: json['timestamp'], // No toString() conversion here
      type: json['type'], // No toString() conversion here
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

  /// Extract Note data from a message
  static Map<String, dynamic>? extractNoteData(WebSocketMessage message) {
    return extractData(message);
  }
  
  /// Extract NoteID from a message
  static String? extractNoteId(WebSocketMessage message) {
    return extractId(message, 'note_id');
  }
    
  /// Extract Notebook data from a message
  static Map<String, dynamic>? extractNotebookData(WebSocketMessage message) {
    return extractData(message);
  }
  
  /// Extract NotebookID from a message
  static String? extractNotebookId(WebSocketMessage message) {
    return extractId(message, 'notebook_id');
  }
    
  /// Extract Block data from a message
  static Map<String, dynamic>? extractBlockData(WebSocketMessage message) {
    return extractData(message);
  }
  
  /// Extract BlockID from a message
  static String? extractBlockId(WebSocketMessage message) {
    return extractId(message, 'block_id');
  }
  
  /// Extract Task data from a message
  static Map<String, dynamic>? extractTaskData(WebSocketMessage message) {
    return extractData(message);
  }
  
  /// Extract TaskID from a message
  static String? extractTaskId(WebSocketMessage message) {
    return extractId(message, 'task_id');
  }
}
