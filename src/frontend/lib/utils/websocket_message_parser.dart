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
    if (payload?.data == null) return false;
    
    switch (modelType) {
      case 'note':
        return payload!.data!.containsKey('note_id');
      case 'notebook':
        return payload!.data!.containsKey('notebook_id');
      case 'block':
        return payload!.data!.containsKey('block_id');
      case 'task':
        return payload!.data!.containsKey('task_id');
      default:
        return false;
    }
  }
  
  /// Get the ID for a specific model type
  String? getModelId(String modelType) {
    if (payload?.data == null) return null;
    
    switch (modelType) {
      case 'note':
        return payload!.data!['note_id']?.toString();
      case 'notebook':
        return payload!.data!['notebook_id']?.toString();
      case 'block':
        return payload!.data!['block_id']?.toString();
      case 'task':
        return payload!.data!['task_id']?.toString();
      default:
        return null;
    }
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
  /// Extract Note data from a message
  static Map<String, dynamic>? extractNoteData(WebSocketMessage message) {
    if (!message.hasModelData('note')) return null;
    return message.payload?.data;
  }
  
  /// Extract NoteID from a message
  static String? extractNoteId(WebSocketMessage message) {
    return message.getModelId('note');
  }
  
  /// Extract Notebook data from a message
  static Map<String, dynamic>? extractNotebookData(WebSocketMessage message) {
    if (!message.hasModelData('notebook')) return null;
    return message.payload?.data;
  }
  
  /// Extract NotebookID from a message
  static String? extractNotebookId(WebSocketMessage message) {
    return message.getModelId('notebook');
  }
  
  /// Extract Block data from a message
  static Map<String, dynamic>? extractBlockData(WebSocketMessage message) {
    if (!message.hasModelData('block')) return null;
    return message.payload?.data;
  }
  
  /// Extract BlockID from a message
  static String? extractBlockId(WebSocketMessage message) {
    return message.getModelId('block');
  }
  
  /// Extract Task data from a message
  static Map<String, dynamic>? extractTaskData(WebSocketMessage message) {
    if (!message.hasModelData('task')) return null;
    return message.payload?.data;
  }
  
  /// Extract TaskID from a message
  static String? extractTaskId(WebSocketMessage message) {
    return message.getModelId('task');
  }
}
