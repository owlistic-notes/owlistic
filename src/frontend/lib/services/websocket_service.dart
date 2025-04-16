import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// Platform-specific imports - don't use conditional imports for the class
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/html.dart' if (dart.library.io) 'package:web_socket_channel/io.dart';

import '../utils/websocket_message_parser.dart';

class WebSocketService {
  static WebSocketService? _instance;
  WebSocketChannel? _channel;
  String _userId = '90a12345-f12a-98c4-a456-513432930000'; // Default user ID
  final String _baseUrl;
  
  bool _isConnected = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isReconnecting = false;
  
  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  // Get the stream of messages
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  
  // Check if connected
  bool get isConnected => _isConnected;
  
  // Private constructor
  WebSocketService._internal() 
      : _baseUrl = dotenv.env['WS_URL'] ?? 'ws://localhost:8082/ws';
  
  // Factory constructor to get instance
  factory WebSocketService() {
    _instance ??= WebSocketService._internal();
    return _instance!;
  }
  
  // Initialize the connection with better error handling and platform awareness
  void connect({String? userId}) {
    if (userId != null) {
      _userId = userId;
    }
    
    if (_isConnected || _isReconnecting) return;
    
    _isReconnecting = true;
    
    try {
      final wsUrl = '$_baseUrl?user_id=$_userId';
      print('WebSocket: Connecting to $wsUrl');
      
      // Create WebSocketChannel using platform-specific implementation
      if (kIsWeb) {
        // Use HtmlWebSocketChannel for web
        _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      } else {
        // Use IOWebSocketChannel for native platforms
        try {
          _channel = IOWebSocketChannel.connect(Uri.parse(wsUrl));
        } catch (e) {
          print('Error creating IOWebSocketChannel: $e');
          // Fallback to basic implementation
          _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
        }
      }
      
      _isConnected = true;
      _isReconnecting = false;
      
      print('WebSocket: Connection established successfully');
      
      // Listen for incoming messages
      _channel!.stream.listen(
        (message) {
          _handleWebSocketMessage(message);
        },
        onDone: _handleDisconnect,
        onError: (error) {
          print('WebSocket error: $error');
          _handleDisconnect();
        },
        cancelOnError: true,
      );
      
      // Start ping timer
      _startPingTimer();
    } catch (e) {
      print('WebSocket: Connection error - $e');
      _isConnected = false;
      _isReconnecting = false;
      _scheduleReconnect();
    }
  }
  
  // Handle disconnection
  void _handleDisconnect() {
    if (!_isConnected) return;
    
    _isConnected = false;
    _channel?.sink.close();
    _pingTimer?.cancel();
    
    _scheduleReconnect();
  }
  
  // Schedule reconnection
  void _scheduleReconnect() {
    // Attempt to reconnect with exponential backoff
    _reconnectTimer?.cancel();
    
    if (!_isReconnecting) {
      _reconnectTimer = Timer(Duration(seconds: 5), () {
        print('WebSocket: Attempting to reconnect...');
        connect();
      });
    }
  }
  
  // Start ping timer to keep connection alive
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(Duration(seconds: 30), (_) {
      sendPing();
    });
  }
  
  // Send a ping message
  void sendPing() {
    if (!_isConnected) return;
    
    try {
      _channel!.sink.add(json.encode({
        'type': 'ping',
      }));
    } catch (e) {
      print('Error sending ping: $e');
    }
  }
  
  // Subscribe to a resource with more flexible options
  void subscribe(String resource, {String? id}) {
    if (!_isConnected) {
      try {
        print('WebSocket not connected, connecting first...');
        connect();
        // Directly send subscribe after connecting
        Future.delayed(Duration(milliseconds: 500), () {
          if (_isConnected) {
            _sendSubscribe(resource, id: id);
          }
        });
        return;
      } catch (e) {
        print('Error during reconnection attempt: $e');
        return;
      }
    }
    
    _sendSubscribe(resource, id: id);
  }
  
  // Helper method to send subscribe message with improved payload format
  void _sendSubscribe(String resource, {String? id}) {
    try {
      final Map<String, dynamic> payload = {
        'resource': resource,
      };
      
      if (id != null) {
        payload['id'] = id;
      }
      
      // For special resource types, add extra identifiers to help server routing
      if (resource == 'note') {
        payload['resource_type'] = 'note';
      } else if (resource == 'notebook') {
        payload['resource_type'] = 'notebook';
      } else if (resource == 'block') {
        payload['resource_type'] = 'block';
      } else if (resource == 'task') {
        payload['resource_type'] = 'task';
      }
      
      // If no ID is provided, indicate this is a global subscription for all items
      if (id == null) {
        payload['global_resource'] = 'true';
      }
      
      final message = {
        'type': 'subscribe',
        'action': 'subscribe',
        'payload': payload,
      };
      
      print('WebSocket: Sending subscribe: ${json.encode(message)}');
      _channel!.sink.add(json.encode(message));
      
      // IMPORTANT: Remove the duplicate subscription to avoid server sending multiple
      // confirmation messages that get concatenated
      // Instead of sending a duplicate immediately, set a longer delay for retry
      // in the WebSocketProvider class
      
      print('Subscribed to $resource ${id != null ? "ID: $id" : "(global)"}');
    } catch (e) {
      print('Error subscribing to $resource: $e');
    }
  }
  
  // Unsubscribe from a resource
  void unsubscribe(String resource, {String? id}) {
    if (!_isConnected) return;
    
    try {
      final Map<String, dynamic> payload = {
        'resource': resource,
      };
      
      if (id != null) {
        payload['id'] = id;
      }
      
      _channel!.sink.add(json.encode({
        'type': 'unsubscribe',
        'action': 'unsubscribe',
        'payload': payload,
      }));
      
      print('Unsubscribed from $resource ${id != null ? "ID: $id" : ""}');
    } catch (e) {
      print('Error unsubscribing from $resource: $e');
    }
  }
  
  // Send block update
  void updateBlock(String id, String content, {String? type}) {
    if (!_isConnected) {
      connect();
      Future.delayed(Duration(milliseconds: 500), () {
        if (_isConnected) {
          _sendBlockUpdate(id, content, type: type);
        }
      });
      return;
    }
    
    _sendBlockUpdate(id, content, type: type);
  }
  
  // Helper to send block update
  void _sendBlockUpdate(String id, String content, {String? type}) {
    try {
      final Map<String, dynamic> payload = {
        'id': id,
        'content': content,
      };
      
      if (type != null) {
        payload['type'] = type;
      }
      
      final message = {
        'type': 'block_update',
        'action': 'update',
        'payload': payload,
      };
      
      print('WebSocket: Sending block update: ${json.encode(message)}');
      _channel!.sink.add(json.encode(message));
      
      print('Sent block update for $id');
    } catch (e) {
      print('Error updating block: $e');
    }
  }
  
  // Send note update
  void updateNote(String id, String title) {
    if (!_isConnected) {
      connect();
      Future.delayed(Duration(milliseconds: 500), () {
        if (_isConnected) {
          _sendNoteUpdate(id, title);
        }
      });
      return;
    }
    
    _sendNoteUpdate(id, title);
  }
  
  // Helper to send note update
  void _sendNoteUpdate(String id, String title) {
    try {
      final message = {
        'type': 'note_update',
        'action': 'update',
        'payload': {
          'id': id,
          'title': title,
        },
      };
      
      print('WebSocket: Sending note update: ${json.encode(message)}');
      _channel!.sink.add(json.encode(message));
      
      print('Sent note update for $id');
    } catch (e) {
      print('Error updating note: $e');
    }
  }

  // General method to send a raw message
  void sendMessage(String message) {
    if (!_isConnected) connect();
    
    try {
      print('WebSocket: Sending raw message: $message');
      _channel!.sink.add(message);
    } catch (e) {
      print('WebSocket: Error sending message: $e');
    }
  }
  
  // Close the connection
  void disconnect() {
    _isConnected = false;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    print('WebSocket disconnected');
  }
  
  // Dispose resources
  void dispose() {
    disconnect();
    _messageController.close();
  }

  // Send a generic event
  void sendEvent(String action, String resourceType, Map<String, dynamic> data) {
    if (_channel == null) {
      print('WebSocketService: Not connected, attempting to connect');
      connect();
      return;
    }

    final message = {
      'type': action,
      'resource': resourceType,
      'data': data,
    };

    try {
      _channel!.sink.add(json.encode(message));
      print('WebSocketService: Sent $action event for $resourceType: ${data['id'] ?? ''}');
    } catch (e) {
      print('WebSocketService: Error sending $action event: $e');
    }
  }

  // Send a block delta update (for real-time collaboration)
  void sendBlockDelta(String id, String delta, int version, String noteId) {
    if (!_isConnected) {
      connect();
      Future.delayed(Duration(milliseconds: 500), () {
        if (_isConnected) {
          _sendBlockDelta(id, delta, version, noteId);
        }
      });
      return;
    }
    
    _sendBlockDelta(id, delta, version, noteId);
  }
  
  // Helper to send block delta
  void _sendBlockDelta(String id, String delta, int version, String noteId) {
    try {
      final message = {
        'type': 'block_delta',
        'action': 'update',
        'payload': {
          'id': id,
          'delta': delta,
          'version': version,
          'note_id': noteId
        },
      };
      
      print('WebSocket: Sending block delta: (message size: ${json.encode(message).length})');
      _channel!.sink.add(json.encode(message));
      
      print('Sent block delta for $id (version: $version)');
    } catch (e) {
      print('Error sending block delta: $e');
    }
  }

  // Helper to parse multiple JSON objects that might be concatenated in a single message
  List<Map<String, dynamic>> _parseMultipleJsonObjects(String input) {
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
              print('WebSocket: Error parsing remaining JSON: $e');
            }
            break;
          }
        }
      } catch (e) {
        print('WebSocket: Error in multi-JSON parser: $e');
        break;
      }
    }
    
    return results;
  }

  // Helper to extract resource type from payload for better logging
  String _extractResourceType(dynamic payload) {
    if (payload == null) return "unknown";
    
    // Try to identify the resource type from the payload
    if (payload is Map) {
      if (payload.containsKey('data')) {
        var data = payload['data'];
        if (data is Map) {
          // CRITICAL FIX: Check for specific ID types
          if (data.containsKey('note_id')) return "note";
          if (data.containsKey('notebook_id')) return "notebook";
          if (data.containsKey('block_id')) return "block";
          if (data.containsKey('task_id')) return "task";
          
          // If we have an ID and can infer the type from context...
          if (data.containsKey('id')) {
            if (data.containsKey('title') && data.containsKey('notebook_id')) return "note";
            if (data.containsKey('name') && data.containsKey('description')) return "notebook";
            if (data.containsKey('content') && data.containsKey('type')) return "block";
            if (data.containsKey('is_completed') || data.containsKey('completed')) return "task";
          }
        }
      }
      
      // Look directly in payload
      if (payload.containsKey('note_id')) return "note";
      if (payload.containsKey('notebook_id')) return "notebook";
      if (payload.containsKey('block_id')) return "block";
      if (payload.containsKey('task_id')) return "task";
      
      // Don't return generic ID anymore as this encourages ID misuse
      if (payload.containsKey('id')) {
        return "unknown"; // Changed from returning the ID
      }
    }
    
    return "unknown";
  }

  void _handleWebSocketMessage(String message) {
    print('WebSocket raw message: $message');
    try {
      // Parse the message with our new parser
      final WebSocketMessage parsedMessage = WebSocketMessage.fromString(message);
      
      // Basic logging for event messages
      if (parsedMessage.type == 'event') {
        final String resourceType = _determineResourceType(parsedMessage);
        final String? resourceId = parsedMessage.getModelId(resourceType);
        
        print('WebSocket EVENT: Type=${parsedMessage.type}, Event=${parsedMessage.event}, ' + 
              'ResourceType=$resourceType, ResourceId=${resourceId ?? "none"}');
      }
      
      // Convert to Map for backwards compatibility with existing code
      final Map<String, dynamic> messageMap = {
        'type': parsedMessage.type,
        'event': parsedMessage.event,
      };
      
      // Add payload if present
      if (parsedMessage.payload != null) {
        messageMap['payload'] = {
          'id': parsedMessage.payload!.id,
          'timestamp': parsedMessage.payload!.timestamp,
        };
        
        // Add data if present
        if (parsedMessage.payload!.data != null) {
          messageMap['payload']['data'] = parsedMessage.payload!.data;
        }
      }
      
      _messageController.add(messageMap);
    } catch (e) {
      print('WebSocket: Error parsing message: $e');
    }
  }
  
  // Helper to determine the resource type from a message
  String _determineResourceType(WebSocketMessage message) {
    // Try to determine from event name first
    final String eventName = message.event.toLowerCase();
    
    if (eventName.contains('note') && !eventName.contains('notebook')) {
      return 'note';
    } else if (eventName.contains('notebook')) {
      return 'notebook';
    } else if (eventName.contains('block')) {
      return 'block';
    } else if (eventName.contains('task')) {
      return 'task';
    }
    
    // If event name doesn't reveal, check payload data
    if (message.hasModelData('note')) {
      return 'note';
    } else if (message.hasModelData('notebook')) {
      return 'notebook';
    } else if (message.hasModelData('block')) {
      return 'block';
    } else if (message.hasModelData('task')) {
      return 'task';
    }
    
    return 'unknown';
  }
}
