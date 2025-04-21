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
  String? _userId; // Remove default user ID - will be set dynamically
  String _baseUrl;
  String? _customUrl;
  final Logger _logger = Logger('WebSocketService');
  
  bool _isConnected = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isReconnecting = false;
  
  // Add local subscription tracking to prevent duplicates at service level
  final Set<String> _activeSubscriptions = {};
  
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

  // Set user ID for WebSocket connection
  void setUserId(String? userId) {
    _userId = userId;
    _logger.info('WebSocket user ID set: ${userId ?? 'null'}');
    
    // Reconnect if we're already connected with new user ID
    if (_isConnected && userId != null) {
      _logger.info('Reconnecting WebSocket with new user ID');
      disconnect();
      connect();
    } else if (_isConnected && userId == null) {
      // If userId is null, disconnect
      _logger.info('User ID is null, disconnecting WebSocket');
      disconnect();
    }
  }

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
    
    // Don't connect if no user ID is provided
    if (_userId == null) {
      _logger.warning('Cannot connect WebSocket: No user ID provided');
      return;
    }
    
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
    // Only reconnect if we have a user ID
    if (_userId != null) {
      _scheduleReconnect();
    }
  }
  
  // Schedule reconnection
  void _scheduleReconnect() {
    // Attempt to reconnect with exponential backoff
    _reconnectTimer?.cancel();
    
    if (!_isReconnecting && _userId != null) {
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
  
  // Clear all subscriptions and state on logout
  void clearState() {
    _logger.info('Clearing WebSocket state');
    // Close existing connection
    disconnect();
    // Clear user ID
    _userId = null;
    // Clear subscription tracking
    _activeSubscriptions.clear();
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
  
  // Subscribe to a resource with duplicate prevention - use this for actual resources (note, block, etc.)
  void subscribe(String resource, {String? id}) {
    if (!_isConnected) {
      try {
        _logger.info('Not connected, connecting first...');
        connect();
        // Directly send subscribe after connecting
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_isConnected) {
            _sendSubscribeToResource(resource, id: id);
          }
        });
        return;
      } catch (e) {
        _logger.error('Error during reconnection attempt', e);
        return;
      }
    }
    
    _sendSubscribeToResource(resource, id: id);
  }
  
  // Subscribe to an event (like block.created) - different format needed
  void subscribeToEvent(String eventType) {
    if (!_isConnected) {
      try {
        _logger.info('Not connected, connecting first...');
        connect();
        // Directly send subscribe after connecting
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_isConnected) {
            _sendSubscribeToEvent(eventType);
          }
        });
        return;
      } catch (e) {
        _logger.error('Error during reconnection attempt', e);
        return;
      }
    }
    
    _sendSubscribeToEvent(eventType);
  }
  
  // Helper method to send subscribe message for resources with duplicate prevention
  void _sendSubscribeToResource(String resource, {String? id}) {
    try {
      // Validate resource and ID
      if (resource.isEmpty) {
        _logger.error('Cannot subscribe with empty resource');
        return;
      }
      
      // Create subscription key for tracking
      final String subscriptionKey = id != null && id.isNotEmpty ? '$resource:$id' : resource;
      
      // Check if already subscribed
      if (_activeSubscriptions.contains(subscriptionKey)) {
        _logger.debug('Already subscribed to $subscriptionKey, skipping duplicate request');
        return;
      }
      
      // Create well-formatted payload
      final Map<String, dynamic> payload = {
        'resource': resource,
      };
      
      // Only add ID if it's not null and not empty
      if (id != null && id.isNotEmpty) {
        payload['id'] = id;
        _logger.debug('Adding ID to subscription payload: $id');
      } else {
        // If no ID is provided, we need to explicitly say this is a global subscription
        payload['global_resource'] = true;  // Boolean flag for global subscription
        _logger.debug('Adding global_resource flag for subscription without ID');
      }
      
      // For special resource types, add extra identifiers to help server routing
      if (resource == 'note') {
        payload['resource_type'] = 'note';
        // Ensure ID is included for note resources if provided
        if (id != null && id.isNotEmpty) {
          payload['note_id'] = id; // Add additional note_id field for compatibility
        }
      } else if (resource == 'notebook') {
        payload['resource_type'] = 'notebook';
        // Ensure ID is included for notebook resources if provided
        if (id != null && id.isNotEmpty) {
          payload['notebook_id'] = id; // Add additional notebook_id field for compatibility
        }
      } else if (resource == 'block') {
        payload['resource_type'] = 'block';
        // Ensure ID is included for block resources if provided
        if (id != null && id.isNotEmpty) {
          payload['block_id'] = id; // Add additional block_id field for compatibility
        }
      } else if (resource == 'task') {
        payload['resource_type'] = 'task';
        // Ensure ID is included for task resources if provided
        if (id != null && id.isNotEmpty) {
          payload['task_id'] = id; // Add additional task_id field for compatibility
        }
      }
      
      // Always include user ID for proper authorization filtering
      if (_userId != null) {
        payload['user_id'] = _userId;
      }
      
      // Construct the final message
      final message = {
        'type': 'subscribe',
        'action': 'subscribe',
        'payload': payload,
      };
      
      // Log the full message for debugging
      _logger.debug('Sending resource subscription: ${json.encode(message)}');
      
      // Make sure channel exists
      if (_channel == null) {
        _logger.error('Cannot send subscribe: WebSocket channel is null');
        return;
      }
      
      _channel!.sink.add(json.encode(message));
      
      // Track this subscription
      _activeSubscriptions.add(subscriptionKey);
      
      _logger.info('Subscribed to resource $resource ${id != null ? "ID: $id" : "(global)"}');
    } catch (e) {
      _logger.error('Error subscribing to resource $resource', e);
    }
  }

  // Helper method to send subscribe message for events (different format than resources)
  void _sendSubscribeToEvent(String eventType) {
    try {
      // Validate event type
      if (eventType.isEmpty) {
        _logger.error('Cannot subscribe with empty event type');
        return;
      }
      
      // Create subscription key for tracking - use consistent format
      final String subscriptionKey = 'event:$eventType';
      
      // Check if already subscribed
      if (_activeSubscriptions.contains(subscriptionKey)) {
        _logger.debug('Already subscribed to event $eventType, skipping duplicate request');
        return;
      }
      
      // Create well-formatted payload for event subscription
      final Map<String, dynamic> payload = {
        'event_type': eventType,
      };
      
      // Always include user ID for proper authorization filtering
      if (_userId != null) {
        payload['user_id'] = _userId;
      }
      
      // Construct the final message - different format for event subscriptions
      final message = {
        'type': 'subscribe',
        'action': 'subscribe_event',
        'payload': payload,
      };
      
      _logger.debug('Sending event subscription: ${json.encode(message)}');
      
      // Make sure channel exists
      if (_channel == null) {
        _logger.error('Cannot send subscribe: WebSocket channel is null');
        return;
      }
      
      _channel!.sink.add(json.encode(message));
      
      // Track this subscription
      _activeSubscriptions.add(subscriptionKey);
      
      _logger.info('Subscribed to event $eventType');
    } catch (e) {
      _logger.error('Error subscribing to event $eventType', e);
    }
  }

  // Unsubscribe from a resource or event
  void unsubscribe(String resource, {String? id}) {
    if (!_isConnected) return;
    
    try {
      // Determine if this is an event subscription or a resource subscription
      final bool isEvent = resource.startsWith('event:');
      
      String subscriptionKey;
      
      if (isEvent) {
        // For event subscriptions, remove the 'event:' prefix
        final eventType = resource.substring(6);
        subscriptionKey = 'event:$eventType';
        _unsubscribeFromEvent(eventType);
      } else {
        // For resource subscriptions
        subscriptionKey = id != null && id.isNotEmpty ? '$resource:$id' : resource;
        _unsubscribeFromResource(resource, id: id);
      }
      
      // Remove from active subscriptions
      _activeSubscriptions.remove(subscriptionKey);
    } catch (e) {
      _logger.error('Error unsubscribing', e);
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
    
    // Clear subscription tracking since connection is closed
    _activeSubscriptions.clear();
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
      
      // Handle subscription confirmations correctly
      if (parsedMessage.type == 'subscription' && parsedMessage.event == 'confirmed') {
        try {
          if (jsonMessage.containsKey('payload')) {
            final payload = jsonMessage['payload'];
            
            // Check if this is an event subscription confirmation
            if (payload.containsKey('event_type')) {
              String eventType = payload['event_type'];
              _logger.info('Event subscription confirmed: $eventType');
            } 
            // Check if this is a resource subscription confirmation
            else if (payload.containsKey('resource')) {
              String resource = payload['resource'];
              String? id = payload['id'];
              _logger.info('Resource subscription confirmed: $resource ${id != null ? "ID: $id" : "(global)"}');
            }
          }
        } catch (e) {
          _logger.error('Error handling subscription confirmation', e);
        }
      } else if (parsedMessage.type == 'ping') {
        // Send pong response to keep connection alive
        sendMessage(json.encode({'type': 'pong'}));
      }
      // Basic logging for event messages
      else if (parsedMessage.type == 'event') {
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
  
  // Get active subscriptions count for debugging
  int get activeSubscriptionsCount => _activeSubscriptions.length;
  
  // Get active subscriptions as list for debugging
  List<String> get activeSubscriptionsList => _activeSubscriptions.toList();
}

// Connection state enum for WebSocketProvider
enum WebSocketConnectionState { disconnected, connecting, connected, error }
