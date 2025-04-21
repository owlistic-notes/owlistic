import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Platform-specific imports - don't use conditional imports for the class
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/websocket_message_parser.dart';
import '../utils/logger.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  WebSocketChannel? _channel;
  String _userId = '5719498e-aaba-4dbd-8385-5b1b8cd49a17'; // Default user ID
  String _baseUrl;
  String? _customUrl;
  final Logger _logger = Logger('WebSocketService');
  
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
  
  // Connection state for WebSocketProvider
  WebSocketConnectionState _connectionState = WebSocketConnectionState.disconnected;
  WebSocketConnectionState get connectionState => _connectionState;
  
  // Private constructor
  WebSocketService._internal() 
      : _baseUrl = dotenv.env['WS_URL'] ?? 'ws://localhost:8082/ws';
  
  // Factory constructor to get instance
  factory WebSocketService() => _instance;

  // Set custom URL
  void setCustomUrl(String url) {
    _customUrl = url;
    _logger.info('Set custom WebSocket URL: $url');
    
    // Reconnect if we're already connected
    if (_isConnected) {
      disconnect();
      connect();
    }
  }
  
  // Get current URL
  String getCurrentUrl() {
    return _customUrl ?? _baseUrl;
  }
  
  // Initialize the connection with better error handling and platform awareness
  Future<void> connect() async {
    if (_isConnected || _isReconnecting) return;
    
    _isReconnecting = true;
    _connectionState = WebSocketConnectionState.connecting;
    
    try {
      final wsUrl = '${_customUrl ?? _baseUrl}?user_id=$_userId';
      _logger.debug('Connecting to $wsUrl');
      
      // Create WebSocketChannel using platform-specific implementation
      if (kIsWeb) {
        // Use HtmlWebSocketChannel for web
        _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      } else {
        // Use IOWebSocketChannel for native platforms
        try {
          _channel = IOWebSocketChannel.connect(Uri.parse(wsUrl));
        } catch (e) {
          _logger.error('Error creating IOWebSocketChannel', e);
          // Fallback to basic implementation
          _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
        }
      }
      
      _isConnected = true;
      _isReconnecting = false;
      _connectionState = WebSocketConnectionState.connected;
      
      _logger.info('Connection established successfully');
      
      // Listen for incoming messages
      _channel!.stream.listen(
        _handleWebSocketMessage,
        onDone: _handleDisconnect,
        onError: (error) {
          _logger.error('WebSocket error', error);
          _connectionState = WebSocketConnectionState.error;
          _handleDisconnect();
        },
        cancelOnError: true,
      );
      
      // Start ping timer
      _startPingTimer();
    } catch (e) {
      _logger.error('Connection error', e);
      _isConnected = false;
      _isReconnecting = false;
      _connectionState = WebSocketConnectionState.error;
      _scheduleReconnect();
    }
  }
  
  // Handle disconnection
  void _handleDisconnect() {
    if (!_isConnected) return;
    
    _isConnected = false;
    _channel?.sink.close();
    _pingTimer?.cancel();
    _connectionState = WebSocketConnectionState.disconnected;
    
    _logger.info('Disconnected, scheduling reconnect');
    _scheduleReconnect();
  }
  
  // Schedule reconnection
  void _scheduleReconnect() {
    // Attempt to reconnect with exponential backoff
    _reconnectTimer?.cancel();
    
    if (!_isReconnecting) {
      _reconnectTimer = Timer(const Duration(seconds: 5), () {
        _logger.info('Attempting to reconnect...');
        connect();
      });
    }
  }
  
  // Start ping timer to keep connection alive
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      sendPing();
    });
  }
  
  // Send a ping message
  void sendPing() {
    if (!_isConnected) return;
    
    try {
      final message = json.encode({'type': 'ping'});
      _channel!.sink.add(message);
      _logger.debug('Sent ping');
    } catch (e) {
      _logger.error('Error sending ping', e);
    }
  }
  
  // Subscribe to a resource with more flexible options
  void subscribe(String resource, {String? id}) {
    if (!_isConnected) {
      try {
        _logger.info('Not connected, connecting first...');
        connect();
        // Directly send subscribe after connecting
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_isConnected) {
            _sendSubscribe(resource, id: id);
          }
        });
        return;
      } catch (e) {
        _logger.error('Error during reconnection attempt', e);
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
      
      _logger.debug('Sending subscribe: ${json.encode(message)}');
      _channel!.sink.add(json.encode(message));
      
      _logger.info('Subscribed to $resource ${id != null ? "ID: $id" : "(global)"}');
    } catch (e) {
      _logger.error('Error subscribing to $resource', e);
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
      
      final message = json.encode({
        'type': 'unsubscribe',
        'action': 'unsubscribe',
        'payload': payload,
      });
      
      _channel!.sink.add(message);
      
      _logger.info('Unsubscribed from $resource ${id != null ? "ID: $id" : ""}');
    } catch (e) {
      _logger.error('Error unsubscribing from $resource', e);
    }
  }
  
  // General method to send a raw message
  void sendMessage(String message) {
    if (!_isConnected) connect();
    
    try {
      _logger.debug('Sending raw message: $message');
      _channel!.sink.add(message);
    } catch (e) {
      _logger.error('Error sending message', e);
    }
  }
  
  // Close the connection
  void disconnect() {
    _isConnected = false;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _connectionState = WebSocketConnectionState.disconnected;
    _logger.info('WebSocket disconnected');
  }
  
  // Dispose resources
  void dispose() {
    disconnect();
    _messageController.close();
  }

  // Send a generic event
  void sendEvent(String action, String resourceType, Map<String, dynamic> data) {
    if (_channel == null) {
      _logger.info('Not connected, attempting to connect');
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
      _logger.info('Sent $action event for $resourceType: ${data['id'] ?? ''}');
    } catch (e) {
      _logger.error('Error sending $action event', e);
    }
  }

  void _handleWebSocketMessage(dynamic message) {
    _logger.debug('Raw message received');
    try {
      // Parse the JSON message
      Map<String, dynamic> jsonMessage;
      if (message is String) {
        jsonMessage = json.decode(message);
      } else {
        // If it's already a Map, just cast it
        jsonMessage = message as Map<String, dynamic>;
      }
      
      // Use our parser to get a structured message object
      final parsedMessage = WebSocketMessage.fromJson(jsonMessage);
      
      // Basic logging for event messages
      if (parsedMessage.type == 'event') {
        String resourceType = 'unknown';
        String? resourceId;
        
        // Try to determine resource type from event name or payload
        if (parsedMessage.event.contains('note') && !parsedMessage.event.contains('notebook')) {
          resourceType = 'note';
          resourceId = WebSocketModelExtractor.extractNoteId(parsedMessage);
        } else if (parsedMessage.event.contains('notebook')) {
          resourceType = 'notebook';
          resourceId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
        } else if (parsedMessage.event.contains('block')) {
          resourceType = 'block';
          resourceId = WebSocketModelExtractor.extractBlockId(parsedMessage);
        }
        
        _logger.debug('EVENT: Type=${parsedMessage.type}, Event=${parsedMessage.event}, ' + 
              'ResourceType=$resourceType, ResourceId=${resourceId ?? "none"}');
      } else if (parsedMessage.type == 'subscription' && parsedMessage.event == 'confirmed') {
        _logger.info('Subscription confirmed: ${jsonMessage['payload']}');
      } else if (parsedMessage.type == 'ping') {
        // Send pong response to keep connection alive
        sendMessage(json.encode({'type': 'pong'}));
      }
      
      // Pass the original message to existing listeners for compatibility
      _messageController.add(jsonMessage);
    } catch (e) {
      _logger.error('Error parsing message', e);
      
      // Try to broadcast raw message as fallback
      try {
        if (message is String) {
          Map<String, dynamic> fallbackJson = {"raw": message};
          _messageController.add(fallbackJson);
        }
      } catch (_) {}
    }
  }
}

// Connection state enum for WebSocketProvider
enum WebSocketConnectionState { disconnected, connecting, connected, error }
