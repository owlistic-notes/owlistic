import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:owlistic/models/subscription.dart';
import 'package:owlistic/services/websocket_service.dart';
import 'package:owlistic/services/auth_service.dart';
import 'package:owlistic/utils/logger.dart';
import 'package:owlistic/models/user.dart';
import 'package:owlistic/viewmodel/websocket_viewmodel.dart';

class WebSocketProvider with ChangeNotifier implements WebSocketViewModel {
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
  final bool _isLoading = false;
  bool _isActive = false;
  
  // Current user from auth service
  User? _currentUser;
  String? _errorMessage;
  
  // Enhanced subscription tracking
  final Set<String> _pendingSubscriptions = {};
  final Set<String> _confirmedSubscriptions = {};
  final Map<String, DateTime> _lastSubscriptionAttempt = {}; // Track when we last tried to subscribe
  static const Duration _subscriptionThrottleTime = Duration(seconds: 10); // Don't retry subscription within this time

  // Map to store event listeners
  final Map<String, List<Function(dynamic)>> _eventListeners = {};

  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  // Standard constructor with required dependencies
  WebSocketProvider({
    required WebSocketService webSocketService,
    required AuthService authService
  }) : _webSocketService = webSocketService,
       _authService = authService {
    _initializeWebSocketListener();
    _setupAuthListeners();
    _initialized = true;
    _logger.info('WebSocketProvider initialized with pre-initialized WebSocketService');
  }

  // Getters
  @override
  bool get isConnected => _isConnected;
  
  @override
  String get lastEventType => _lastEventType;
  
  @override
  String get lastEventAction => _lastEventAction;
  
  @override
  DateTime? get lastEventTime => _lastEventTime;
  
  @override
  int get messageCount => _messageCount;
  
  @override
  User? get currentUser => _currentUser;
  
  @override
  bool get isLoading => _isLoading;
  
  @override
  bool get isActive => _isActive;
  
  @override
  bool get isInitialized => _initialized;
  
  @override
  String? get errorMessage => _errorMessage;
  
  @override
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
  
  // Getters for subscription debugging
  @override
  Set<String> get confirmedSubscriptions => Set.from(_confirmedSubscriptions);
  
  @override
  Set<String> get pendingSubscriptions => Set.from(_pendingSubscriptions);
  
  @override
  int get totalSubscriptions => _confirmedSubscriptions.length + _pendingSubscriptions.length;
  
  @override
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  // Setup auth listeners for improved auth state synchronization
  void _setupAuthListeners() {
    try {
      _logger.debug('Setting up auth listeners');
      
      // Listen to auth state changes to connect/disconnect WebSocket
      final authStream = _authService.authStateChanges;
      _authSubscription = authStream.listen((isLoggedIn) {
        _logger.info('Auth state changed: isLoggedIn=$isLoggedIn');
        
        if (isLoggedIn) {
          // User logged in - get current user and connect WebSocket
          _authService.getUserProfile().then((user) {
            _currentUser = user;
            if (user != null) {
              _logger.info('Setting WebSocket auth data after login');
              
              // First set the auth token - primary authentication method 
              _webSocketService.setAuthToken(AuthService.token);
              
              // Then set the user ID as additional identification
              _webSocketService.setUserId(user.id);
              
              // Ensure connection is established
              ensureConnected();
            }
          });
        } else {
          // User logged out - disconnect WebSocket
          _logger.info('User logged out, disconnecting WebSocket');
          _currentUser = null;
          clearAllSubscriptions();
          disconnect();
          _webSocketService.setAuthToken(null); // Clear token first
          _webSocketService.setUserId(null);    // Then clear user ID
        }
      });
          
      // Check current auth state immediately
      _authService.getUserProfile().then((user) {
        _currentUser = user;
        if (user != null) {
          _logger.info('User already logged in with ID: ${user.id}, connecting WebSocket');
          
          // First set the auth token - primary authentication method 
          _webSocketService.setAuthToken(AuthService.token);
          
          // Then set the user ID as additional identification
          _webSocketService.setUserId(user.id);
          
          // Ensure connection is established
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
    
    // Listen to connection state changes
    _webSocketService.connectionStateStream.listen((connected) {
      _logger.info('WebSocket connection state changed: connected=$connected');
      _isConnected = connected;
      
      // If connection was restored, restore subscriptions
      if (connected && (_pendingSubscriptions.isNotEmpty || _confirmedSubscriptions.isNotEmpty)) {
        _restoreSubscriptions();
      }
      
      notifyListeners();
    });
    
    _initialized = true;
    _isConnected = _webSocketService.isConnected;
  }
  
  // Restore subscriptions after reconnection
  Future<void> _restoreSubscriptions() async {
    _logger.info('Restoring subscriptions after reconnection');
    
    // Get all subscriptions to restore
    final subscriptionsToRestore = Set<String>.from(_confirmedSubscriptions);
    subscriptionsToRestore.addAll(_pendingSubscriptions);
    
    // Clear current tracking since we're going to resubscribe
    _confirmedSubscriptions.clear();
    _pendingSubscriptions.clear();
    
    // Batch resubscribe in small groups to avoid overwhelming the connection
    int count = 0;
    for (final subscription in subscriptionsToRestore) {
      if (subscription.startsWith('event:')) {
        // Handle event subscriptions
        final eventType = subscription.substring(6); // Remove 'event:' prefix
        await subscribeToEvent(eventType);
      } else if (subscription.contains(':')) {
        // Handle resource:id subscriptions
        final parts = subscription.split(':');
        await subscribe(parts[0], id: parts[1]);
      } else {
        // Handle global resource subscriptions
        await subscribe(subscription);
      }
      
      // Small delay between subscriptions
      count++;
      if (count % 5 == 0) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    
    _logger.info('Restored ${subscriptionsToRestore.length} subscriptions');
  }

  // Ensure connection is established
  @override
  Future<bool> ensureConnected() async {
    // Get the token directly from AuthService to ensure it's current
    final token = AuthService.token;
    
    // Check if we have authentication before allowing connection
    if (token == null) {
      _logger.warning('Cannot connect WebSocket: No authentication token');
      return false;
    }
    
    if (_webSocketService.isConnected) {
      _isConnected = true;
      notifyListeners();
      return true;
    }
    
    // Always set the current token before connecting to ensure it's fresh
    _webSocketService.setAuthToken(token);
    
    if (_currentUser != null) {
      _webSocketService.setUserId(_currentUser!.id);
    }
    
    _logger.info('Connecting WebSocket...');
    await _webSocketService.connect();
    
    // Wait a short time for connection to establish
    await Future.delayed(const Duration(milliseconds: 300));
    
    _isConnected = _webSocketService.isConnected;
    
    if (_isConnected) {
      _logger.info('WebSocket connection established');
    } else {
      _logger.warning('WebSocket connection failed');
    }
    
    notifyListeners();
    return _isConnected;
  }

  // Clear all subscriptions
  @override
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
    _lastSubscriptionAttempt.clear();
    
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
      
      String? subscriptionKey;
      
      // Handle resource subscription confirmations
      if (payload['resource'] != null) {
        final resource = payload['resource']?.toString();
        if (resource == null || resource.isEmpty) {
          _logger.warning('Received subscription confirmation with missing resource');
          return;
        }
        
        final id = payload['id']?.toString();
        subscriptionKey = id != null && id.isNotEmpty ? '$resource:$id' : resource;
      } 
      // Handle event subscription confirmations
      else if (payload['event_type'] != null) {
        final eventType = payload['event_type']?.toString();
        if (eventType == null || eventType.isEmpty) {
          _logger.warning('Received subscription confirmation with missing event_type');
          return;
        }
        
        subscriptionKey = 'event:$eventType';
      }
      
      if (subscriptionKey != null) {
        _logger.info('Confirmed subscription: $subscriptionKey');
        _pendingSubscriptions.remove(subscriptionKey);
        _confirmedSubscriptions.add(subscriptionKey);
        
        notifyListeners();
      } else {
        _logger.warning('Could not determine subscription key from payload: $payload');
      }
    } catch (e) {
      _logger.error('Error handling subscription confirmation', e);
    }
  }

  // Register event handler with improved logging and duplicate prevention
  @override
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
  @override
  void removeEventListener(String type, String event) {
    final String key = '$type:$event';
    if (_eventHandlers.containsKey(key)) {
      _logger.debug('Removing all handlers for $key');
      _eventHandlers.remove(key);
    }
  }

  // Register an event listener
  @override
  void on(String eventName, Function(dynamic) callback) {
    _eventListeners[eventName] ??= [];
    _eventListeners[eventName]!.add(callback);
  }

  // Remove an event listener
  @override
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

  // Subscribe to a resource - with duplicate subscription prevention
  @override
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
    if (_confirmedSubscriptions.contains(subscriptionKey)) {
      _logger.debug('Already confirmed subscription to $subscriptionKey, skipping');
      return;
    }
    
    if (_pendingSubscriptions.contains(subscriptionKey)) {
      // Check if we've recently tried to subscribe to this resource
      final lastAttempt = _lastSubscriptionAttempt[subscriptionKey];
      if (lastAttempt != null && 
          DateTime.now().difference(lastAttempt) < _subscriptionThrottleTime) {
        _logger.debug('Subscription to $subscriptionKey is pending and was attempted recently, throttling');
        return;
      }
      _logger.debug('Subscription to $subscriptionKey is pending but attempt was long ago, retrying');
    }
    
    _logger.info('Subscribing to $resource${id != null && id.isNotEmpty ? " ID: $id" : " (global)"}');
    
    // Update last attempt time
    _lastSubscriptionAttempt[subscriptionKey] = DateTime.now();
    
    // Use the WebSocketService subscribe method for resources
    _webSocketService.subscribe(resource, id: id);
    
    _pendingSubscriptions.add(subscriptionKey);
    notifyListeners();
  }
  
  // Subscribe to an event type (like block.created)
  @override
  Future<void> subscribeToEvent(String eventType) async {
    // Check if user is authenticated
    if (_currentUser == null) {
      _logger.warning('Cannot subscribe to event: No authenticated user');
      return;
    }
    
    await ensureConnected();
    
    // Properly format event type for subscription tracking
    final String subscriptionKey = 'event:$eventType';
    
    // Check if already subscribed to avoid duplicates
    if (_confirmedSubscriptions.contains(subscriptionKey)) {
      _logger.debug('Already confirmed subscription to event $eventType, skipping');
      return;
    }
    
    if (_pendingSubscriptions.contains(subscriptionKey)) {
      // Check if we've recently tried to subscribe to this event
      final lastAttempt = _lastSubscriptionAttempt[subscriptionKey];
      if (lastAttempt != null && 
          DateTime.now().difference(lastAttempt) < _subscriptionThrottleTime) {
        _logger.debug('Subscription to event $eventType is pending and was attempted recently, throttling');
        return;
      }
      _logger.debug('Subscription to event $eventType is pending but attempt was long ago, retrying');
    }
    
    _logger.info('Subscribing to event: $eventType');
    
    // Update last attempt time
    _lastSubscriptionAttempt[subscriptionKey] = DateTime.now();
    
    // Use the WebSocketService subscribeToEvent method
    _webSocketService.subscribeToEvent(eventType);
    
    _pendingSubscriptions.add(subscriptionKey);
    notifyListeners();
  }

  // Check if subscribed to a resource
  @override
  bool isSubscribed(String resource, {String? id}) {
    final subscriptionKey = id != null && id.isNotEmpty ? '$resource:$id' : resource;
    return _confirmedSubscriptions.contains(subscriptionKey) || 
           _pendingSubscriptions.contains(subscriptionKey);
  }
  
  // Check if subscribed to an event
  @override
  bool isSubscribedToEvent(String eventType) {
    final subscriptionKey = 'event:$eventType';
    return _confirmedSubscriptions.contains(subscriptionKey) || 
           _pendingSubscriptions.contains(subscriptionKey);
  }
  
  // Unsubscribe from an event
  @override
  void unsubscribeFromEvent(String eventType) {
    final subscriptionKey = 'event:$eventType';
    
    _logger.info('Unsubscribing from event: $eventType');
    _webSocketService.unsubscribeFromEvent(eventType);
    
    _pendingSubscriptions.remove(subscriptionKey);
    _confirmedSubscriptions.remove(subscriptionKey);
    _lastSubscriptionAttempt.remove(subscriptionKey);
    
    notifyListeners();
  }

  // Batch subscribe to multiple resources simultaneously, with duplicate prevention
  @override
  Future<void> batchSubscribe(List<Subscription> subscriptions) async {
    // Check if user is authenticated
    if (_currentUser == null) {
      _logger.warning('Cannot batch subscribe: No authenticated user');
      return;
    }
    
    await ensureConnected();
    
    if (subscriptions.isEmpty) return;
    
    // Filter out subscriptions that are already confirmed or pending recently
    final List<Subscription> newSubscriptions = subscriptions.where((sub) {
      final subscriptionKey = sub.id != null ? '${sub.resource}:${sub.id}' : sub.resource;
      
      // Skip if already confirmed
      if (_confirmedSubscriptions.contains(subscriptionKey)) {
        return false;
      }
      
      // Skip if pending and recently attempted
      if (_pendingSubscriptions.contains(subscriptionKey)) {
        final lastAttempt = _lastSubscriptionAttempt[subscriptionKey];
        if (lastAttempt != null && 
            DateTime.now().difference(lastAttempt) < _subscriptionThrottleTime) {
          return false;
        }
      }
      
      return true;
    }).toList();
    
    if (newSubscriptions.isEmpty) {
      _logger.info('No new subscriptions to process in batch');
      return;
    }
    
    _logger.info('Batch subscribing to ${newSubscriptions.length} resources');
    
    // Process in batches of 5 to avoid overwhelming the connection
    for (int i = 0; i < newSubscriptions.length; i += 5) {
      final end = (i + 5 < newSubscriptions.length) ? i + 5 : newSubscriptions.length;
      final batch = newSubscriptions.sublist(i, end);
      
      // Process this batch
      for (final sub in batch) {
        final subscriptionKey = sub.id != null ? '${sub.resource}:${sub.id}' : sub.resource;
        
        _logger.debug('Subscribing to ${sub.resource}${sub.id != null ? " ID: ${sub.id}" : ""}');
        _pendingSubscriptions.add(subscriptionKey);
        _lastSubscriptionAttempt[subscriptionKey] = DateTime.now();
        _webSocketService.subscribe(sub.resource, id: sub.id);
      }
      
      // Add a small delay between batches
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    notifyListeners();
  }

  // Unsubscribe from a resource
  @override
  void unsubscribe(String resource, {String? id}) {
    final subscriptionKey = id != null ? '$resource:$id' : resource;
    
    _webSocketService.unsubscribe(resource, id: id);
    
    _pendingSubscriptions.remove(subscriptionKey);
    _confirmedSubscriptions.remove(subscriptionKey);
    _lastSubscriptionAttempt.remove(subscriptionKey);
  }

  // Force reconnection with better subscription handling
  @override
  Future<bool> reconnect() async {
    _logger.info('Forcing WebSocket reconnection');
    
    // Get a fresh token before reconnecting
    final token = AuthService.token;
    if (token == null) {
      _logger.warning('Cannot reconnect: No authentication token');
      return false;
    }
    
    // Save current subscriptions before disconnecting
    final subscriptionsToRestore = Set<String>.from(_confirmedSubscriptions);
    _confirmedSubscriptions.clear();
    _pendingSubscriptions.clear();
    
    // Disconnect
    _webSocketService.disconnect();
    
    // Wait for disconnection to complete
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Set fresh auth data
    _webSocketService.setAuthToken(token);
    if (_currentUser != null) {
      _webSocketService.setUserId(_currentUser!.id);
    }
    
    // Connect with fresh auth data
    await _webSocketService.connect();
    
    // Wait for connection
    await Future.delayed(const Duration(milliseconds: 500));
    
    _isConnected = _webSocketService.isConnected;
    
    // Resubscribe to all previous subscriptions
    if (_isConnected && subscriptionsToRestore.isNotEmpty) {
      int count = 0;
      for (final subscription in subscriptionsToRestore) {
        if (subscription.startsWith('event:')) {
          await subscribeToEvent(subscription.substring(6)); // Remove 'event:' prefix
        } else if (subscription.contains(':')) {
          final parts = subscription.split(':');
          await subscribe(parts[0], id: parts[1]);
        } else {
          await subscribe(subscription);
        }
        
        // Add delay every 5 subscriptions
        count++;
        if (count % 5 == 0) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    }
    
    notifyListeners();
    return _isConnected;
  }

  // Disconnect the WebSocket connection
  @override
  void disconnect() {
    _logger.info('Disconnecting WebSocket');
    _webSocketService.disconnect();
    _isConnected = false;
    notifyListeners();
  }

  // Clean up WebSocket state on logout
  @override
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

  // Debug info method
  @override
  Map<String, dynamic> getDebugInfo() {
    return {
      'isConnected': _isConnected,
      'confirmedSubscriptions': _confirmedSubscriptions.length,
      'pendingSubscriptions': _pendingSubscriptions.length,
      'connectionState': _webSocketService.connectionState.toString(),
      'messageCount': _messageCount,
      'lastEventTime': _lastEventTime?.toString() ?? 'never',
      'lastEventType': _lastEventType,
      'lastEventAction': _lastEventAction,
      'hasUser': _currentUser != null,
    };
  }
  
  // MVP Pattern implementation
  @override
  void activate() {
    _isActive = true;
    _logger.info('WebSocketProvider activated');
    
    // Ensure connection when activated
    ensureConnected();
    
    notifyListeners();
  }
  
  @override
  void deactivate() {
    _isActive = false;
    _logger.info('WebSocketProvider deactivated');
    notifyListeners();
  }
  
  @override
  void resetState() {
    _logger.info('Resetting WebSocketProvider state');
    clearAllSubscriptions();
    _lastEventType = '';
    _lastEventAction = '';
    _lastEventTime = null;
    _messageCount = 0;
    _currentUser = null;
    notifyListeners();
  }

  // Cleanup
  @override
  void dispose() {
    _subscription?.cancel();
    _authSubscription?.cancel();
    _eventHandlers.clear();
    _messageController.close();
    super.dispose();
  }
}
