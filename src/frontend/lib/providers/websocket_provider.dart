import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/websocket_service.dart';
import '../models/subscription.dart';

class WebSocketProvider with ChangeNotifier {
  // Singleton WebSocket service
  final WebSocketService _webSocketService = WebSocketService();
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
      },
      onError: (error) {
        print('WebSocketProvider: Error from stream: $error');
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

  // Central handler for all incoming WebSocket messages
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
      
      // Handle events
      if (type == 'event') {
        Future.microtask(() {
          // Get handlers for this exact event
          final handlers = _eventHandlers['$type:$event'] ?? [];
          
          if (handlers.isNotEmpty) {
            for (final handler in handlers) {
              try {
                handler(message);
              } catch (e) {
                print('WebSocketProvider: Error in event handler: $e');
              }
            }
            notifyListeners();
          }
        });
      }
    } catch (e) {
      print('WebSocketProvider: Error handling message: $e');
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
      print('WebSocketProvider: Error handling subscription confirmation: $e');
    }
  }

  // Register event handler
  void addEventListener(String type, String event, Function(Map<String, dynamic>) handler) {
    final String key = '$type:$event';
    
    _eventHandlers[key] ??= [];
    
    // Only add if not already registered
    if (!_eventHandlers[key]!.contains(handler)) {
      _eventHandlers[key]!.add(handler);
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

  // Send a block update
  void sendBlockUpdate(String id, String content, {String? type}) {
    _webSocketService.updateBlock(id, content, type: type);
  }

  // Send a note update
  void sendNoteUpdate(String id, String title) {
    _webSocketService.updateNote(id, title);
  }

  // Send a create request
  void sendCreate(String resourceType, Map<String, dynamic> data) {
    _webSocketService.sendEvent('create', resourceType, data);
  }

  // Send an update request
  void sendUpdate(String resourceType, String id, Map<String, dynamic> data) {
    data['id'] = id; // Ensure ID is included
    _webSocketService.sendEvent('update', resourceType, data);
  }

  // Send a delete request
  void sendDelete(String resourceType, String id) {
    _webSocketService.sendEvent('delete', resourceType, {'id': id});
  }

  // Send a block delta update
  void sendBlockDelta(String id, String delta, int version, String noteId) {
    _webSocketService.sendBlockDelta(id, delta, version, noteId);
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
