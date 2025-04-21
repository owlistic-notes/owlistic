import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/subscription.dart';
import '../services/websocket_service.dart';
import '../services/auth_service.dart';
import '../utils/logger.dart';
import '../models/user.dart';

class WebSocketProvider with ChangeNotifier {
  // Singleton WebSocket service
  final Logger _logger = Logger('WebSocketProvider');
  final WebSocketService _webSocketService;
  final AuthService _authService;
  StreamSubscription? _subscription;
  StreamSubscription? _authSubscription;
  
  // Map of event handlers by type:event
  final Map<String, List<Function(Map<String, dynamic>)>> _eventHandlers = {};
  
  // Connection status and debug info
  bool _isConnected = false;
  String _lastEventType = '';
  String _lastEventAction = '';
  DateTime? _lastEventTime;
  int _messageCount = 0;
  bool _initialized = false;
  
  // Current user from auth service
  User? _currentUser;
  
  // Subscription tracking
  final Set<String> _pendingSubscriptions = {};
  final Set<String> _confirmedSubscriptions = {};

  // Map to store event listeners
  final Map<String, List<Function(dynamic)>> _eventListeners = {};

  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  // Get the stream of messages
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  // Standard constructor with required dependencies
  WebSocketProvider({
    required WebSocketService webSocketService,
    required AuthService authService
  }) : _webSocketService = webSocketService,
       _authService = authService {
    _initializeWebSocketListener();
    _setupAuthListeners();
  }

  // Getters for connection state and debug info
  bool get isConnected => _isConnected;
  String get lastEventType => _lastEventType;
  String get lastEventAction => _lastEventAction;
  DateTime? get lastEventTime => _lastEventTime;
  int get messageCount => _messageCount;
  User? get currentUser => _currentUser;

  // Setup auth listeners for improved auth state synchronization
  void _setupAuthListeners() {
    try {
      _logger.debug('Setting up auth listeners');
      
      // Listen to auth state changes to connect/disconnect WebSocket
      final authStream = _authService.authStateChanges;
      if (authStream != null) {
        _authSubscription = authStream.listen((isLoggedIn) {
          _logger.info('Auth state changed: isLoggedIn=$isLoggedIn');
          
          if (isLoggedIn) {
            // User logged in - get current user and connect WebSocket
            _authService.getUserProfile().then((user) {
              _currentUser = user;
              if (user != null) {
                _logger.info('Setting WebSocket user ID from auth: ${user.id}');
                _webSocketService.setUserId(user.id);
                ensureConnected();
              }
            });
          } else {
            // User logged out - disconnect WebSocket
            _logger.info('User logged out, disconnecting WebSocket');
            _currentUser = null;
            clearAllSubscriptions();
            disconnect();
            _webSocketService.setUserId(null);
          }
        });
      }
      
      // Check current auth state immediately
      _authService.getUserProfile().then((user) {
        _currentUser = user;
        if (user != null) {
          _logger.info('User already logged in with ID: ${user.id}, connecting WebSocket');
          _webSocketService.setUserId(user.id);
          ensureConnected();
        } else {
          _logger.info('No logged in user found');
        }
      });
    } catch (e) {
      _logger.error("Error initializing WebSocketProvider auth listeners", e);
    }
  }

  // Initialize the listener
  void _initializeWebSocketListener() {
    if (_initialized) return;
    
    // Do not connect immediately - wait for auth state
    
    // Set up the message listener
    _subscription = _webSocketService.messageStream.listen(
      (message) {
        _messageCount++;
        _handleWebSocketMessage(message);
        _processMessage(message);
      },
      onError: (error) {
        _logger.error('Error from stream', error);
        _isConnected = false;
        notifyListeners();
      }
    );
    
    _initialized = true;
    _isConnected = _webSocketService.isConnected;
  }

  // Ensure connection is established
  Future<bool> ensureConnected() async {
    // Check if we have a user before allowing connection
    if (_currentUser == null) {
      _logger.warning('Cannot connect WebSocket: No authenticated user');
      return false;
    }
    
    if (_webSocketService.isConnected) {
      _isConnected = true;
      notifyListeners();
      return true;
    }
    
    // Make sure WebSocket service has the current user ID
    _webSocketService.setUserId(_currentUser!.id);
    _webSocketService.connect();
    
    // Wait a short time for connection to establish
    await Future.delayed(const Duration(milliseconds: 500));
    
    _isConnected = _webSocketService.isConnected;
    notifyListeners();
    
    return _isConnected;
  }

  // Clear all subscriptions
  void clearAllSubscriptions() {
    _logger.info('Clearing all WebSocket subscriptions');
    
    // Unsubscribe from all confirmed subscriptions
    for (final subscription in _confirmedSubscriptions) {
      if (subscription.contains(':')) {
        final parts = subscription.split(':');
        _webSocketService.unsubscribe(parts[0], id: parts[1]);
      } else {
        _webSocketService.unsubscribe(subscription);
      }
    }
    
    // Clear subscription sets
    _pendingSubscriptions.clear();
    _confirmedSubscriptions.clear();
    
    notifyListeners();
  }

  // Central handler for all incoming WebSocket messages with improved block handling
  void _handleWebSocketMessage(Map<String, dynamic> message) {
    try {
      final String type = message['type'] ?? 'unknown';
      final String event = message['event'] ?? 'unknown';
      
      // Update debug info
      _lastEventType = type;
      _lastEventAction = event;
      _lastEventTime = DateTime.now();
      
      // For subscription confirmations
      if (type == 'subscription' && event == 'confirmed') {
        _handleSubscriptionConfirmation(message);
        return;
      }
      
      // Detailed logging for block-related events
      final String eventKey = '$type:$event';
      if (type == 'event' && (event.contains('block') || event.startsWith('block.'))) {
        _logger.debug('Received block event - $event');
        _logger.debug('Looking for handlers for key: $eventKey');
        _logger.debug('Available handlers: ${_eventHandlers.keys.join(', ')}');
      }
      
      // Handle events - immediate processing is better than Future.microtask
      if (type == 'event') {
        // Get handlers for this exact event
        final handlers = _eventHandlers[eventKey] ?? [];
        
        if (handlers.isNotEmpty) {
          _logger.debug('Found ${handlers.length} handlers for $eventKey');
          for (final handler in handlers) {
            try {
              // Call handler synchronously to avoid timing issues
              handler(message);
            } catch (e) {
              _logger.error('Error in event handler', e);
            }
          }
          notifyListeners();
        } else {
          _logger.debug('No handlers registered for $eventKey');
        }
      }
    } catch (e) {
      _logger.error('Error handling message', e);
    }
  }

  // Handle subscription confirmation messages
  void _handleSubscriptionConfirmation(Map<String, dynamic> message) {
    try {
      final payload = message['payload'];
      if (payload == null) {
        _logger.warning('Received subscription confirmation with null payload');
        return;
      }
      
      final resource = payload['resource']?.toString();
      if (resource == null || resource.isEmpty) {
        _logger.warning('Received subscription confirmation with missing resource');
        return;
      }
      
      final id = payload['id']?.toString();
      final subscriptionKey = id != null && id.isNotEmpty ? '$resource:$id' : resource;
      
      _logger.info('Confirmed subscription: $subscriptionKey');
      _pendingSubscriptions.remove(subscriptionKey);
      _confirmedSubscriptions.add(subscriptionKey);
      
      notifyListeners();
    } catch (e) {
      _logger.error('Error handling subscription confirmation', e);
    }
  }

  // Register event handler with improved logging and duplicate prevention
  void addEventListener(String type, String event, Function(Map<String, dynamic>) handler) {
    final String key = '$type:$event';
    
    _eventHandlers[key] ??= [];
    
    // Check if handler is already registered to avoid duplicates
    bool isDuplicate = false;
    for (var existingHandler in _eventHandlers[key]!) {
      if (existingHandler == handler) {
        isDuplicate = true;
        break;
      }
    }
    
    if (!isDuplicate) {
      _logger.debug('Adding event handler for $key');
      _eventHandlers[key]!.add(handler);
    } else {
      _logger.debug('Handler for $key already registered, skipping');
    }
  }

  // Remove event listener with improved consistency
  void removeEventListener(String type, String event) {
    final String key = '$type:$event';
    if (_eventHandlers.containsKey(key)) {
      _logger.debug('Removing all handlers for $key');
      _eventHandlers.remove(key);
    }
  }

  // Register an event listener
  void on(String eventName, Function(dynamic) callback) {
    _eventListeners[eventName] ??= [];
    _eventListeners[eventName]!.add(callback);
  }

  // Remove an event listener
  void off(String eventName, [Function(dynamic)? callback]) {
    if (callback == null) {
      _eventListeners.remove(eventName);
    } else if (_eventListeners.containsKey(eventName)) {
      _eventListeners[eventName]!.remove(callback);
    }
  }

  // Trigger event listeners for an event
  void _triggerEvent(String eventName, dynamic data) {
    if (_eventListeners.containsKey(eventName)) {
      for (final callback in _eventListeners[eventName]!) {
        callback(data);
      }
    }
  }

  // Process incoming WebSocket message
  void _processMessage(dynamic message) {
    // Pass the message to the messageController
    _messageController.add(message);
    
    // After processing, trigger appropriate events
    if (message is Map && message.containsKey('event')) {
      final eventName = message['event'];
      final eventData = message['data'];
      
      // Trigger event listeners
      _triggerEvent(eventName, eventData);
    }
  }

  // Subscribe to a resource - only if user is authenticated
  Future<void> subscribe(String resource, {String? id}) async {
    // Check if user is authenticated
    if (_currentUser == null) {
      _logger.warning('Cannot subscribe: No authenticated user');
      return;
    }
    
    await ensureConnected();
    
    // Properly format resource and id for subscription
    final String subscriptionKey = id != null && id.isNotEmpty ? '$resource:$id' : resource;
    
    // Check if already subscribed to avoid duplicates
    if (_confirmedSubscriptions.contains(subscriptionKey) || 
        _pendingSubscriptions.contains(subscriptionKey)) {
      _logger.debug('Already subscribed to $subscriptionKey, skipping');
      return;
    }
    
    _logger.info('Subscribing to $resource${id != null && id.isNotEmpty ? " ID: $id" : " (global)"}');
    
    // Validate ID to make sure it's not empty
    if (id != null && id.isEmpty) {
      _logger.warning('Empty ID provided for $resource subscription, treating as global');
      _webSocketService.subscribe(resource);
    } else {
      _webSocketService.subscribe(resource, id: id);
    }
    
    _pendingSubscriptions.add(subscriptionKey);
    notifyListeners();
  }

  // Batch subscribe to multiple resources simultaneously
  Future<void> batchSubscribe(List<Subscription> subscriptions) async {
    // Check if user is authenticated
    if (_currentUser == null) {
      _logger.warning('Cannot batch subscribe: No authenticated user');
      return;
    }
    
    await ensureConnected();
    
    if (subscriptions.isEmpty) return;
    
    _logger.info('Batch subscribing to ${subscriptions.length} resources');
    
    // Process in batches of 5 to avoid overwhelming the connection
    for (int i = 0; i < subscriptions.length; i += 5) {
      final end = (i + 5 < subscriptions.length) ? i + 5 : subscriptions.length;
      final batch = subscriptions.sublist(i, end);
      
      // Process this batch
      for (final sub in batch) {
        final subscriptionKey = sub.id != null ? '${sub.resource}:${sub.id}' : sub.resource;
        
        if (!_confirmedSubscriptions.contains(subscriptionKey) && 
            !_pendingSubscriptions.contains(subscriptionKey)) {
          _logger.debug('Subscribing to ${sub.resource}${sub.id != null ? " ID: ${sub.id}" : ""}');
          _pendingSubscriptions.add(subscriptionKey);
          _webSocketService.subscribe(sub.resource, id: sub.id);
        }
      }
      
      // Add a small delay between batches
      await Future.delayed(Duration(milliseconds: 100));
    }
  }

  // Unsubscribe from a resource
  void unsubscribe(String resource, {String? id}) {
    final subscriptionKey = id != null ? '$resource:$id' : resource;
    
    _webSocketService.unsubscribe(resource, id: id);
    
    _pendingSubscriptions.remove(subscriptionKey);
    _confirmedSubscriptions.remove(subscriptionKey);
  }

  // Force reconnection with resubscription
  Future<bool> reconnect() async {
    // Save current subscriptions before disconnecting
    final subscriptionsToRestore = Set<String>.from(_confirmedSubscriptions);
    _confirmedSubscriptions.clear();
    _pendingSubscriptions.clear();
    
    _webSocketService.disconnect();
    await Future.delayed(Duration(milliseconds: 500));
    _webSocketService.connect();
    
    await Future.delayed(Duration(milliseconds: 500));
    _isConnected = _webSocketService.isConnected;
    
    // Resubscribe to all previous subscriptions
    if (_isConnected && subscriptionsToRestore.isNotEmpty) {
      for (final subscription in subscriptionsToRestore) {
        if (subscription.contains(':')) {
          final parts = subscription.split(':');
          await subscribe(parts[0], id: parts[1]);
        } else {
          await subscribe(subscription);
        }
      }
    }
    
    notifyListeners();
    return _isConnected;
  }

  // Clean up WebSocket state on logout
  void clearOnLogout() {
    _logger.info('Cleaning up WebSocket provider state on logout');
    
    // Clear all subscriptions
    clearAllSubscriptions();
    
    // Disconnect WebSocket
    disconnect();
    
    // Clear current user
    _currentUser = null;
    
    // Clear WebSocket service state
    _webSocketService.clearState();
    
    // Reset connection status
    _isConnected = false;
    
    notifyListeners();
  }

  // Cleanup
  @override
  void dispose() {
    _subscription?.cancel();
    _authSubscription?.cancel();
    _eventHandlers.clear();
    _webSocketService.dispose();
    super.dispose();
  }
}
