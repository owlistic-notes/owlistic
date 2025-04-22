import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/websocket_service.dart';
import '../models/subscription.dart';
import '../utils/logger.dart';

class WebSocketProvider with ChangeNotifier {
  // Singleton WebSocket service
  final WebSocketService _webSocketService = WebSocketService();
  final Logger _logger = Logger('WebSocketProvider');
  StreamSubscription? _subscription;
  
  // Map of event handlers by type:event
  final Map<String, List<Function(Map<String, dynamic>)>> _eventHandlers = {};
  
  // Connection status and debug info
  bool _isConnected = false;
  String _lastEventType = '';
  String _lastEventAction = '';
  DateTime? _lastEventTime;
  int _messageCount = 0;
  bool _initialized = false;
  
  // Subscription tracking
  final Set<String> _pendingSubscriptions = {};
  final Set<String> _confirmedSubscriptions = {};

  // Map to store event listeners
  final Map<String, List<Function(dynamic)>> _eventListeners = {};

  // Constructor - initialize and connect immediately
  WebSocketProvider() {
    _initializeWebSocketListener();
    ensureConnected();
  }

  // Getters for connection state and debug info
  bool get isConnected => _isConnected;
  String get lastEventType => _lastEventType;
  String get lastEventAction => _lastEventAction;
  DateTime? get lastEventTime => _lastEventTime;
  int get messageCount => _messageCount;

  // Initialize the listener
  void _initializeWebSocketListener() {
    if (_initialized) return;
    
    // Connect immediately
    _webSocketService.connect();
    
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
    if (_webSocketService.isConnected) {
      _isConnected = true;
      notifyListeners();
      return true;
    }
    
    _webSocketService.connect();
    
    // Wait a short time for connection to establish
    await Future.delayed(const Duration(milliseconds: 500));
    
    _isConnected = _webSocketService.isConnected;
    notifyListeners();
    
    return _isConnected;
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
      if (payload == null) return;
      
      final resource = payload['resource']?.toString() ?? '';
      final id = payload['id']?.toString();
      final subscriptionKey = id != null ? '$resource:$id' : resource;
      
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
      _eventHandlers[key]!.add(handler);
      _logger.debug('Registered handler for $key (now ${_eventHandlers[key]!.length} handlers)');
    } else {
      _logger.debug('Handler already registered for $key');
    }
  }

  // Remove an event handler
  void removeEventListener(String type, String event, [Function(Map<String, dynamic>)? handler]) {
    final String key = '$type:$event';
    
    if (handler == null) {
      // Remove all handlers for this event type
      _eventHandlers.remove(key);
    } else if (_eventHandlers.containsKey(key)) {
      // Remove specific handler
      _eventHandlers[key]!.remove(handler);
      
      // Clean up if no handlers remain
      if (_eventHandlers[key]!.isEmpty) {
        _eventHandlers.remove(key);
      }
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
    // The existing message processing code...
    
    // After processing, trigger appropriate events
    if (message is Map && message.containsKey('event')) {
      final eventName = message['event'];
      final eventData = message['data'];
      
      // Trigger event listeners
      _triggerEvent(eventName, eventData);
    }
  }

  // Subscribe to a resource
  Future<void> subscribe(String resource, {String? id}) async {
    await ensureConnected();
    
    // Create a subscription key for tracking
    final subscriptionKey = id != null ? '$resource:$id' : resource;
    
    // Only subscribe if we haven't already subscribed to this resource
    if (!_confirmedSubscriptions.contains(subscriptionKey) && 
        !_pendingSubscriptions.contains(subscriptionKey)) {
      _pendingSubscriptions.add(subscriptionKey);
      
      _webSocketService.subscribe(resource, id: id);
      
      // Set up a retry with a longer delay (4 seconds)
      Future.delayed(Duration(seconds: 4), () {
        if (_pendingSubscriptions.contains(subscriptionKey) && _isConnected) {
          _webSocketService.subscribe(resource, id: id);
        }
      });
    }
  }

  // Batch subscribe to multiple resources simultaneously
  Future<void> batchSubscribe(List<Subscription> subscriptions) async {
    await ensureConnected();
    
    if (subscriptions.isEmpty) return;
    
    // Process in batches of 5 to avoid overwhelming the connection
    for (int i = 0; i < subscriptions.length; i += 5) {
      final end = (i + 5 < subscriptions.length) ? i + 5 : subscriptions.length;
      final batch = subscriptions.sublist(i, end);
      
      // Process this batch
      for (final sub in batch) {
        final subscriptionKey = sub.id != null ? '${sub.resource}:${sub.id}' : sub.resource;
        
        if (!_confirmedSubscriptions.contains(subscriptionKey) && 
            !_pendingSubscriptions.contains(subscriptionKey)) {
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

  // Cleanup
  @override
  void dispose() {
    _subscription?.cancel();
    _webSocketService.dispose();
    _eventHandlers.clear();
    super.dispose();
  }
}
