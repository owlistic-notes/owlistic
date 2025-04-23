import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Platform-specific imports - don't use conditional imports for the class
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/websocket_message_parser.dart';
import '../utils/logger.dart';
import 'auth_service.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  WebSocketChannel? _channel;
  String? _userId; // Keep for backward compatibility but don't use for auth
  String _baseUrl;
  String? _customUrl;
  String? _authToken;
  final Logger _logger = Logger('WebSocketService');
  
  bool _isConnected = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isReconnecting = false;
  int _reconnectAttempt = 0;
  static const int _maxReconnectAttempts = 5;
  
  // Add local subscription tracking to prevent duplicates at service level
  final Set<String> _activeSubscriptions = {};
  
  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
      
  // Add connection state stream for better event propagation
  final StreamController<bool> _connectionStateController = 
      StreamController<bool>.broadcast();
  
  // Get the stream of messages
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  
  // Get the connection state stream
  Stream<bool> get connectionStateStream => _connectionStateController.stream;
  
  // Check if connected
  bool get isConnected => _isConnected;
  
  // Connection state for WebSocketProvider
  WebSocketConnectionState _connectionState = WebSocketConnectionState.disconnected;
  WebSocketConnectionState get connectionState => _connectionState;
  
  // Private constructor - use the correct API path for WebSocket
  WebSocketService._internal() 
      : _baseUrl = dotenv.env['WS_URL'] ?? 'ws://localhost:8080/ws';
  
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

  // Set auth token for WebSocket connection
  void setAuthToken(String? token) {
    _authToken = token;
    _logger.info('WebSocket auth token set: ${token != null ? '******' : 'null'}');
    
    // Reconnect if we're already connected with new token
    if (_isConnected && token != null) {
      _logger.info('Reconnecting WebSocket with new auth token');
      disconnect();
      connect();
    } else if (_isConnected && token == null) {
      // If token is null, disconnect
      _logger.info('Auth token is null, disconnecting WebSocket');
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
    
    // Don't connect if no auth token is provided
    if (_authToken == null) {
      _logger.warning('Cannot connect WebSocket: No auth token provided');
      return;
    }
    
    _isReconnecting = true;
    _connectionState = WebSocketConnectionState.connecting;
    _connectionStateController.add(false); // Still connecting
    
    try {
      // Include auth token in URL as a query parameter - the websocket_auth_middleware expects this
      String wsUrl = '${_customUrl ?? _baseUrl}?token=$_authToken';
      _logger.debug('Connecting to WebSocket URL: $wsUrl');
      
      // Add connection timeout
      Future<void> connectionFuture;
      
      // Create WebSocketChannel using platform-specific implementation
      if (kIsWeb) {
        // Use WebSocketChannel for web
        _channel = WebSocketChannel.connect(
          Uri.parse(wsUrl)
        );
        connectionFuture = Future.value();
      } else {
        // Use IOWebSocketChannel for native platforms with timeout
        try {
          _channel = IOWebSocketChannel.connect(
            Uri.parse(wsUrl),
            pingInterval: const Duration(seconds: 20),
          );
          connectionFuture = Future.value();
        } catch (e) {
          _logger.error('Error creating IOWebSocketChannel', e);
          // Fallback to basic implementation
          _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
          connectionFuture = Future.value();
        }
      }
      
      // Add a timeout to prevent hanging indefinitely
      await connectionFuture.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('WebSocket connection timed out');
        }
      );
      
      _isConnected = true;
      _connectionState = WebSocketConnectionState.connected;
      _connectionStateController.add(true); // Now connected
      _reconnectAttempt = 0; // Reset reconnect counter on successful connection
      
      _logger.info('WebSocket connection established successfully');
      
      // Listen for incoming messages
      _channel!.stream.listen(
        _handleWebSocketMessage,
        onDone: _handleDisconnect,
        onError: (error) {
          _logger.error('WebSocket error', error);
          _connectionState = WebSocketConnectionState.error;
          _handleDisconnect();
        },
        cancelOnError: false,
      );
      
      // Start ping timer
      _startPingTimer();
    } catch (e) {
      _logger.error('WebSocket connection error', e);
      _isConnected = false;
      _connectionState = WebSocketConnectionState.error;
      _connectionStateController.add(false);
      _scheduleReconnect();
    } finally {
      // Make sure we reset the reconnecting flag regardless of success or failure
      _isReconnecting = false;
    }
  }
  
  // Handle disconnection with improved state management
  void _handleDisconnect() {
    if (!_isConnected) return;
    
    _isConnected = false;
    _connectionState = WebSocketConnectionState.disconnected;
    _connectionStateController.add(false);
    
    _pingTimer?.cancel();
    _pingTimer = null;
    
    try {
      _channel?.sink.close();
    } catch (e) {
      _logger.error('Error closing WebSocket channel', e);
    }
    
    _channel = null;
    
    _logger.info('WebSocket disconnected, scheduling reconnect');
    
    // Only reconnect if we have an auth token
    if (_authToken != null) {
      _scheduleReconnect();
    }
  }
  
  // Schedule reconnection with exponential backoff
  void _scheduleReconnect() {
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      _logger.warning('Maximum reconnection attempts reached');
      return;
    }
    
    _reconnectAttempt++;
    
    // Calculate delay with exponential backoff (1s, 2s, 4s, 8s, 16s)
    int delayMs = 1000 * (1 << (_reconnectAttempt - 1));
    if (delayMs > 30000) delayMs = 30000; // Cap at 30 seconds
    
    _logger.info('Scheduling reconnect attempt $_reconnectAttempt/$_maxReconnectAttempts in ${delayMs}ms');
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      _logger.info('Attempting to reconnect...');
      connect();
    });
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
    // Clear auth data
    _userId = null;
    _authToken = null;
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
      // Validate resource
      if (resource.isEmpty) {
        _logger.error('Cannot subscribe with empty resource');
        return;
      }
      
      // Create subscription key for tracking
      final String subscriptionKey = id != null && id.isNotEmpty ? '$resource:$id' : resource;
      
      // Check if already subscribed to avoid duplicates
      if (_activeSubscriptions.contains(subscriptionKey)) {
        _logger.debug('Already subscribed to $subscriptionKey, skipping duplicate request');
        return;
      }
      
      // Simple format that matches exactly what the server expects
      final message = {
        'type': 'subscribe',
        'event': 'subscribe',
        'payload': {
          'resource': resource,
          if (id != null && id.isNotEmpty) 'id': id,
        }
      };
      
      _logger.debug('Sending subscription message: ${json.encode(message)}');
      
      // Send the message
      if (_channel != null) {
        _channel!.sink.add(json.encode(message));
        // Track this subscription
        _activeSubscriptions.add(subscriptionKey);
        _logger.info('Subscribed to resource $resource ${id != null ? "ID: $id" : "(global)"}');
      } else {
        _logger.error('Cannot send subscribe: WebSocket channel is null');
      }
    } catch (e) {
      _logger.error('Error subscribing to resource $resource', e);
    }
  }

  // Helper method to send subscribe message for events
  void _sendSubscribeToEvent(String eventType) {
    try {
      // Validate event type
      if (eventType.isEmpty) {
        _logger.error('Cannot subscribe with empty event type');
        return;
      }
      
      // Create subscription key for tracking
      final String subscriptionKey = 'event:$eventType';
      
      // Check if already subscribed to avoid duplicates
      if (_activeSubscriptions.contains(subscriptionKey)) {
        _logger.debug('Already subscribed to event $eventType, skipping duplicate request');
        return;
      }
      
      // Simple format that matches exactly what the server expects
      final message = {
        'type': 'subscribe',
        'event': 'subscribe',
        'payload': {
          'event_type': eventType,
        }
      };
      
      _logger.debug('Sending event subscription: ${json.encode(message)}');
      
      if (_channel != null) {
        _channel!.sink.add(json.encode(message));
        // Track this subscription
        _activeSubscriptions.add(subscriptionKey);
        _logger.info('Subscribed to event $eventType');
      } else {
        _logger.error('Cannot send subscribe: WebSocket channel is null');
      }
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
        _sendUnubscribeFromEvent(eventType);
      } else {
        // For resource subscriptions
        subscriptionKey = id != null && id.isNotEmpty ? '$resource:$id' : resource;
        _sendUnsubscribeFromResource(resource, id: id);
      }
      
      // Remove from active subscriptions
      _activeSubscriptions.remove(subscriptionKey);
    } catch (e) {
      _logger.error('Error unsubscribing', e);
    }
  }
  
  // Helper method to send subscribe message for resources with duplicate prevention
  void _sendUnsubscribeFromResource(String resource, {String? id}) {
    try {
      // Validate resource
      if (resource.isEmpty) {
        _logger.error('Cannot unsubscribe with empty resource');
        return;
      }
      
      // Create subscription key for tracking
      final String subscriptionKey = id != null && id.isNotEmpty ? '$resource:$id' : resource;
      
      // Check if already unsubscribed
      if (!_activeSubscriptions.contains(subscriptionKey)) {
        _logger.debug('Already unsubscribed from $subscriptionKey, skipping');
        return;
      }
      
      // Create unsubscribe message
      final message = {
        'type': 'unsubscribe',
        'payload': {
          'resource': resource,
          if (id != null && id.isNotEmpty) 'id': id,
        },
      };
      
      // Send the message
      if (_channel != null) {
        _channel!.sink.add(json.encode(message));
        
        // Remove from active subscriptions
        _activeSubscriptions.remove(subscriptionKey);
        
        _logger.info('Unsubscribed from resource $resource ${id != null ? "ID: $id" : "(global)"}');
      } else {
        _logger.error('Cannot send unsubscribe: WebSocket channel is null');
      }
    } catch (e) {
      _logger.error('Error unsubscribing from resource $resource', e);
    }
  }

  // Helper method to send unsubscribe message for events
  void _sendUnubscribeFromEvent(String eventType) {
    try {
      // Validate event type
      if (eventType.isEmpty) {
        _logger.error('Cannot unsubscribe with empty event type');
        return;
      }
      
      // Create subscription key for tracking
      final String subscriptionKey = 'event:$eventType';
      
      // Check if already unsubscribed
      if (!_activeSubscriptions.contains(subscriptionKey)) {
        _logger.debug('Already unsubscribed from event $eventType, skipping');
        return;
      }
      
      // Create payload specifically for event unsubscription
      final Map<String, dynamic> payload = {
        'event_type': eventType,
      };
      
      // Always include user ID for proper authorization filtering
      if (_userId != null) {
        payload['user_id'] = _userId;
      }
      
      // Construct the message - use the format expected by the server
      final message = {
        'type': 'unsubscribe',
        'action': 'unsubscribe',
        'payload': payload,
      };
      
      _logger.debug('Sending event unsubscription: ${json.encode(message)}');
      
      // Make sure channel exists
      if (_channel == null) {
        _logger.error('Cannot send unsubscribe: WebSocket channel is null');
        return;
      }
      
      _channel!.sink.add(json.encode(message));
      
      // Remove from active subscriptions
      _activeSubscriptions.remove(subscriptionKey);
      
      _logger.info('Unsubscribed from event $eventType');
    } catch (e) {
      _logger.error('Error unsubscribing from event $eventType', e);
    }
  }

  // Unsubscribe from an event
  void unsubscribeFromEvent(String eventType) {
    if (!_isConnected) {
      _logger.warning('Cannot unsubscribe: WebSocket not connected');
      return;
    }
    
    _sendUnubscribeFromEvent(eventType);
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
    _connectionStateController.close();
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

  // Handle incoming WebSocket messages with better error handling
  void _handleWebSocketMessage(dynamic message) {
    try {
      if (message is String) {
        _logger.debug('Received string message');
        
        // Split the message if it contains multiple JSON objects
        List<String> jsonMessages = _splitJsonMessages(message);
        
        for (String jsonStr in jsonMessages) {
          // Parse and process each JSON object individually
          try {
            Map<String, dynamic> jsonMessage = json.decode(jsonStr);
            _processJsonMessage(jsonMessage);
          } catch (e) {
            _logger.error('Error parsing JSON object: $e');
            _logger.debug('Problematic JSON: $jsonStr');
          }
        }
      } else {
        // If it's already a Map, just process it directly
        Map<String, dynamic> jsonMessage = message as Map<String, dynamic>;
        _logger.debug('Received message object');
        _processJsonMessage(jsonMessage);
      }
    } catch (e) {
      _logger.error('Error processing message', e);
      
      // Log the raw message for debugging
      if (message is String) {
        _logger.debug('Raw message that caused error: $message');
      }
      
      // Try to broadcast raw message as fallback
      try {
        if (message is String) {
          Map<String, dynamic> fallbackJson = {"raw": message, "error": e.toString()};
          _messageController.add(fallbackJson);
        }
      } catch (_) {}
    }
  }

  // Process a single JSON message object
  void _processJsonMessage(Map<String, dynamic> jsonMessage) {
    // Handle ping messages with immediate response
    if (jsonMessage['type'] == 'ping') {
      _logger.debug('Received ping message from server, responding with pong');
      sendMessage(json.encode({'type': 'pong'}));
      return;
    }
    
    // Handle pong messages (response to our pings)
    if (jsonMessage['type'] == 'pong') {
      _logger.debug('Received pong response from server');
      return;
    }
    
    // Use our parser to get a structured message object for other messages
    final parsedMessage = WebSocketParser.parse(jsonMessage);
    if (parsedMessage != null) {
      // Handle subscription confirmations
      if (parsedMessage.type == 'subscription' && parsedMessage.event == 'confirmed') {
        _handleSubscriptionConfirmation(parsedMessage.payload);
      }
      // Handle events
      else if (parsedMessage.type == 'event') {
        _logEventMessage(parsedMessage);
      }
    }
    
    // Pass the message to existing listeners
    _messageController.add(jsonMessage);
  }

  // Helper method to split a string that might contain multiple JSON objects
  List<String> _splitJsonMessages(String message) {
    List<String> result = [];
    int depth = 0;
    int startPos = 0;
    bool inString = false;
    bool escaped = false;
    
    for (int i = 0; i < message.length; i++) {
      var char = message[i];
      
      if (inString) {
        if (escaped) {
          // Skip this character as it's escaped
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
      } else {
        if (char == '"') {
          inString = true;
        } else if (char == '{') {
          if (depth == 0) {
            startPos = i;
          }
          depth++;
        } else if (char == '}') {
          depth--;
          if (depth == 0) {
            // We found a complete JSON object
            String jsonObj = message.substring(startPos, i + 1);
            result.add(jsonObj);
          }
        }
      }
    }
    
    // If no valid JSON objects were found, return the original message
    if (result.isEmpty) {
      result.add(message);
    }
    
    _logger.debug('Split message into ${result.length} JSON objects');
    return result;
  }

  // Helper to handle subscription confirmations
  void _handleSubscriptionConfirmation(Map<String, dynamic> payload) {
    try {
      // Check if this is an event subscription confirmation
      if (payload.containsKey('event_type')) {
        String eventType = payload['event_type'];
        _logger.info('Event subscription confirmed: $eventType');
      } 
      // Check if this is a resource subscription confirmation
      else if (payload.containsKey('resource')) {
        String resource = payload['resource'];
        String? id = payload['id'];
        
        // Fix: Properly handle empty string IDs
        if (id == null || id.isEmpty) {
          _logger.info('Resource subscription confirmed: $resource (global)');
        } else {
          _logger.info('Resource subscription confirmed: $resource ID: $id');
        }
        
        // Update tracking with proper key - empty ID means global subscription
        final String subscriptionKey = (id == null || id.isEmpty) ? resource : '$resource:$id';
        _activeSubscriptions.add(subscriptionKey);
      }
    } catch (e) {
      _logger.error('Error handling subscription confirmation', e);
    }
  }

  // Helper to log event messages
  void _logEventMessage(WebSocketMessage message) {
    String resourceType = message.resourceType ?? 'unknown';
    String? resourceId;
    
    // Extract IDs based on resource type
    if (resourceType == 'note') {
      resourceId = WebSocketModelExtractor.extractNoteId(message);
    } else if (resourceType == 'notebook') {
      resourceId = WebSocketModelExtractor.extractNotebookId(message);
    } else if (resourceType == 'block') {
      resourceId = WebSocketModelExtractor.extractBlockId(message);
    }
    
    _logger.info('EVENT RECEIVED: Type=${message.type}, Event=${message.event}, ' + 
          'ResourceType=$resourceType, ResourceId=${resourceId ?? "none"}');
  }

  // Get active subscriptions count for debugging
  int get activeSubscriptionsCount => _activeSubscriptions.length;
  
  // Get active subscriptions as list for debugging
  List<String> get activeSubscriptionsList => _activeSubscriptions.toList();
}

// Connection state enum for WebSocketProvider
enum WebSocketConnectionState { disconnected, connecting, connected, error }
