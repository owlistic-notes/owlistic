import 'dart:convert';

/// Base class for WebSocket message parsing
class WebSocketMessageParser {
  /// Parse a raw WebSocket message into structured format
  static List<Map<String, dynamic>> parseRawMessage(String rawMessage) {
    try {
      // Handle the case where multiple JSON objects might be concatenated
      return _parseMultipleJsonObjects(rawMessage);
    } catch (e) {
      print('Error parsing WebSocket message: $e');
      return [];
    }
  }

  /// Extract the message type from a message
  static String getMessageType(Map<String, dynamic> message) {
    return message['type'] ?? 'unknown';
  }

  /// Extract the event name from a message
  static String getEventName(Map<String, dynamic> message) {
    return message['event'] ?? '';
  }
  
  /// Extract entity ID from a WebSocket message based on entity type
  static String? extractEntityId(Map<String, dynamic> message, String entityType) {
    // First try the specialized extractors
    switch (entityType) {
      case 'note':
        return NoteMessageParser.extractNoteId(message);
      case 'notebook':
        return NotebookMessageParser.extractNotebookId(message);
      case 'block':
        return BlockMessageParser.extractBlockId(message);
      case 'task':
        return TaskMessageParser.extractTaskId(message);
      default:
        // Generic fallback extractor
        return _extractGenericId(message, entityType);
    }
  }
  
  /// Extract data from payload.payload.data structure (deeply nested)
  static Map<String, dynamic>? extractNestedData(Map<String, dynamic> message) {
    try {
      if (message.containsKey('payload')) {
        final payload = message['payload'];
        
        if (payload is Map<String, dynamic>) {
          // Try doubly nested structure (payload.payload.data)
          if (payload.containsKey('payload')) {
            final innerPayload = payload['payload'];
            
            if (innerPayload is Map<String, dynamic> && 
                innerPayload.containsKey('data')) {
              return innerPayload['data'];
            }
          }
          
          // Try regular structure (payload.data)
          if (payload.containsKey('data')) {
            return payload['data'];
          }
        }
      }
      return null;
    } catch (e) {
      print('Error extracting nested data: $e');
      return null;
    }
  }
  
  /// Helper to parse multiple JSON objects that might be concatenated
  static List<Map<String, dynamic>> _parseMultipleJsonObjects(String input) {
    List<Map<String, dynamic>> results = [];
    String remaining = input.trim();
    
    // Process as long as there's content to parse
    while (remaining.isNotEmpty) {
      try {
        // Try to find the end of a JSON object
        int objectDepth = 0;
        int endIndex = -1;
        bool inString = false;
        bool escaped = false;
        
        for (int i = 0; i < remaining.length; i++) {
          final char = remaining[i];
          
          if (inString) {
            if (char == '\\' && !escaped) {
              escaped = true;
            } else if (char == '"' && !escaped) {
              inString = false;
            } else {
              escaped = false;
            }
          } else {
            if (char == '"') {
              inString = true;
            } else if (char == '{') {
              objectDepth++;
            } else if (char == '}') {
              objectDepth--;
              if (objectDepth == 0) {
                endIndex = i + 1;
                break;
              }
            }
          }
        }
        
        if (endIndex > 0) {
          // Extract the complete JSON object
          String jsonStr = remaining.substring(0, endIndex);
          remaining = remaining.substring(endIndex).trim();
          
          // Parse the JSON object
          Map<String, dynamic> jsonObj = json.decode(jsonStr);
          results.add(jsonObj);
        } else {
          // If no complete JSON object was found, try to parse whatever is left
          if (remaining.isNotEmpty) {
            try {
              Map<String, dynamic> jsonObj = json.decode(remaining);
              results.add(jsonObj);
            } catch (e) {
              print('Error parsing remaining JSON: $e');
            }
            break;
          }
        }
      } catch (e) {
        print('Error in multi-JSON parser: $e');
        break;
      }
    }
    
    return results;
  }
  
  /// Generic ID extractor that looks for common ID patterns
  static String? _extractGenericId(Map<String, dynamic> message, String entityType) {
    final data = extractNestedData(message);
    if (data != null) {
      // Try entity-specific ID format (entity_id)
      final specificIdKey = '${entityType}_id';
      if (data.containsKey(specificIdKey)) {
        return data[specificIdKey]?.toString();
      }
      
      // Try generic id field
      if (data.containsKey('id')) {
        return data['id']?.toString();
      }
    }
    return null;
  }
}

/// Message parser specialized for Note entities
class NoteMessageParser {
  /// Extract note ID from a WebSocket message
  static String? extractNoteId(Map<String, dynamic> message) {
    final data = WebSocketMessageParser.extractNestedData(message);
    if (data != null && data.containsKey('note_id')) {
      return data['note_id']?.toString();
    }
    return null;
  }
  
  /// Extract notebook ID from a note-related message
  static String? extractNotebookIdFromNoteMessage(Map<String, dynamic> message) {
    final data = WebSocketMessageParser.extractNestedData(message);
    if (data != null && data.containsKey('notebook_id')) {
      return data['notebook_id']?.toString();
    }
    return null;
  }
  
  /// Extract complete note data
  static Map<String, dynamic>? extractNoteData(Map<String, dynamic> message) {
    final data = WebSocketMessageParser.extractNestedData(message);
    if (data != null && 
        (data.containsKey('note_id') || 
         (data.containsKey('title') && data.containsKey('notebook_id')))) {
      return data;
    }
    return null;
  }
}

/// Message parser specialized for Notebook entities
class NotebookMessageParser {
  /// Extract notebook ID from a WebSocket message
  static String? extractNotebookId(Map<String, dynamic> message) {
    final data = WebSocketMessageParser.extractNestedData(message);
    if (data != null && data.containsKey('notebook_id')) {
      return data['notebook_id']?.toString();
    }
    return null;
  }
  
  /// Extract complete notebook data
  static Map<String, dynamic>? extractNotebookData(Map<String, dynamic> message) {
    final data = WebSocketMessageParser.extractNestedData(message);
    if (data != null && 
        (data.containsKey('notebook_id') || 
         (data.containsKey('name') && data.containsKey('description')))) {
      return data;
    }
    return null;
  }
}

/// Message parser specialized for Block entities
class BlockMessageParser {
  /// Extract block ID from a WebSocket message
  static String? extractBlockId(Map<String, dynamic> message) {
    final data = WebSocketMessageParser.extractNestedData(message);
    if (data != null && data.containsKey('block_id')) {
      return data['block_id']?.toString();
    }
    return null;
  }
  
  /// Extract note ID from a block-related message
  static String? extractNoteIdFromBlockMessage(Map<String, dynamic> message) {
    final data = WebSocketMessageParser.extractNestedData(message);
    if (data != null && data.containsKey('note_id')) {
      return data['note_id']?.toString();
    }
    return null;
  }
  
  /// Extract complete block data
  static Map<String, dynamic>? extractBlockData(Map<String, dynamic> message) {
    final data = WebSocketMessageParser.extractNestedData(message);
    if (data != null && 
        (data.containsKey('block_id') || 
         (data.containsKey('content') && data.containsKey('note_id')))) {
      return data;
    }
    return null;
  }
}

/// Message parser specialized for Task entities
class TaskMessageParser {
  /// Extract task ID from a WebSocket message
  static String? extractTaskId(Map<String, dynamic> message) {
    final data = WebSocketMessageParser.extractNestedData(message);
    if (data != null && data.containsKey('task_id')) {
      return data['task_id']?.toString();
    }
    return null;
  }
  
  /// Extract complete task data
  static Map<String, dynamic>? extractTaskData(Map<String, dynamic> message) {
    final data = WebSocketMessageParser.extractNestedData(message);
    if (data != null && 
        (data.containsKey('task_id') || 
         (data.containsKey('title') && data.containsKey('is_completed')))) {
      return data;
    }
    return null;
  }
}
