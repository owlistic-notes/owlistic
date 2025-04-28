import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodel/websocket_viewmodel.dart';
import '../utils/logger.dart';
import '../models/subscription.dart';

/// A utility class to help manage WebSocket subscriptions in widgets
class WebSocketSubscriptionManager {
  final Logger _logger = Logger('WebSocketSubscriptionManager');
  final Set<String> _activeSubscriptions = {};
  late WebSocketViewModel _webSocketViewModel;
  bool _initialized = false;
  BuildContext? _context;
  
  /// Initialize the subscription manager with a build context
  void initialize(BuildContext context) {
    _context = context;
    _webSocketViewModel = context.watch<WebSocketViewModel>();
    _initialized = true;
    _logger.debug('WebSocketSubscriptionManager initialized');
  }
  
  /// Check if the manager is properly initialized
  void _checkInitialized() {
    if (!_initialized) {
      throw StateError('WebSocketSubscriptionManager not initialized. Call initialize() first.');
    }
  }
  
  /// Subscribe to a resource, with optional ID
  Future<void> subscribe(String resource, {String? id}) async {
    _checkInitialized();
    final key = id != null ? '$resource:$id' : resource;
    
    if (_activeSubscriptions.contains(key)) {
      _logger.debug('Already subscribed to $key, skipping');
      return;
    }
    
    _activeSubscriptions.add(key);
    await _webSocketViewModel.subscribe(resource, id: id);
    _logger.debug('Subscribed to $resource${id != null ? ':$id' : ''}');
  }
  
  /// Subscribe to an event type
  Future<void> subscribeToEvent(String eventType) async {
    _checkInitialized();
    final key = 'event:$eventType';
    
    if (_activeSubscriptions.contains(key)) {
      _logger.debug('Already subscribed to event $eventType, skipping');
      return;
    }
    
    _activeSubscriptions.add(key);
    await _webSocketViewModel.subscribeToEvent(eventType);
  }
  
  /// Subscribe to multiple resources at once
  Future<void> batchSubscribe(List<Subscription> subscriptions) async {
    _checkInitialized();
    final List<Subscription> newSubscriptions = [];
    
    for (final sub in subscriptions) {
      final key = sub.id != null ? '${sub.resource}:${sub.id}' : sub.resource;
      if (!_activeSubscriptions.contains(key)) {
        _activeSubscriptions.add(key);
        newSubscriptions.add(sub);
      }
    }
    
    if (newSubscriptions.isNotEmpty) {
      await _webSocketViewModel.batchSubscribe(newSubscriptions);
      _logger.debug('Batch subscribed to ${newSubscriptions.length} resources');
    }
  }
  
  /// Unsubscribe from a resource
  void unsubscribe(String resource, {String? id}) {
    _checkInitialized();
    final key = id != null ? '$resource:$id' : resource;
    
    if (_activeSubscriptions.contains(key)) {
      _activeSubscriptions.remove(key);
      _webSocketViewModel.unsubscribe(resource, id: id);
      _logger.debug('Unsubscribed from $resource${id != null ? ':$id' : ''}');
    }
  }
  
  /// Unsubscribe from an event type
  void unsubscribeFromEvent(String eventType) {
    _checkInitialized();
    final key = 'event:$eventType';
    
    if (_activeSubscriptions.contains(key)) {
      _activeSubscriptions.remove(key);
      _webSocketViewModel.unsubscribeFromEvent(eventType);
      _logger.debug('Unsubscribed from event $eventType');
    }
  }
  
  /// Clean up all active subscriptions
  void cleanupSubscriptions() {
    if (!_initialized) return;
    
    _logger.debug('Cleaning up ${_activeSubscriptions.length} active subscriptions');
    
    for (final key in _activeSubscriptions) {
      if (key.startsWith('event:')) {
        // Handle event subscription
        final eventType = key.substring(6);
        _webSocketViewModel.unsubscribeFromEvent(eventType);
      } else if (key.contains(':')) {
        // Handle resource:id subscription
        final parts = key.split(':');
        _webSocketViewModel.unsubscribe(parts[0], id: parts[1]);
      } else {
        // Handle global resource subscription
        _webSocketViewModel.unsubscribe(key);
      }
    }
    
    _activeSubscriptions.clear();
  }
  
  /// Check if already subscribed to a resource
  bool isSubscribed(String resource, {String? id}) {
    _checkInitialized();
    final key = id != null ? '$resource:$id' : resource;
    return _activeSubscriptions.contains(key);
  }
  
  /// Check if already subscribed to an event
  bool isSubscribedToEvent(String eventType) {
    _checkInitialized();
    return _activeSubscriptions.contains('event:$eventType');
  }
  
  // Add event listener with tracking for cleanup
  void on(String eventName, Function(dynamic) handler) {
    _checkInitialized();
    _webSocketViewModel.on(eventName, handler);
    // Track event handlers by combining event name and handler identity
    _activeSubscriptions.add('handler:$eventName:${handler.hashCode}');
    _logger.debug('Added event listener for $eventName');
  }
  
  // Remove event listener
  void off(String eventName, [Function(dynamic)? handler]) {
    if (!_initialized) return;
    
    _webSocketViewModel.off(eventName, handler);
    
    if (handler != null) {
      _activeSubscriptions.remove('handler:$eventName:${handler.hashCode}');
    } else {
      // Remove all handlers for this event
      _activeSubscriptions.removeWhere((key) => key.startsWith('handler:$eventName:'));
    }
    
    _logger.debug('Removed event listener for $eventName');
  }
}

/// A mixin that provides WebSocketSubscriptionManager functionality for StatefulWidgets
mixin WebSocketSubscriptionMixin<T extends StatefulWidget> on State<T> {
  final WebSocketSubscriptionManager _subscriptionManager = WebSocketSubscriptionManager();
  
  /// Initialize the subscription manager in initState
  void initWebSocketSubscriptions() {
    _subscriptionManager.initialize(context);
  }
  
  /// Subscribe to a resource, with optional ID
  Future<void> subscribe(String resource, {String? id}) => 
      _subscriptionManager.subscribe(resource, id: id);
  
  /// Subscribe to an event type
  Future<void> subscribeToEvent(String eventType) =>
      _subscriptionManager.subscribeToEvent(eventType);
  
  /// Subscribe to multiple resources at once
  Future<void> batchSubscribe(List<Subscription> subscriptions) =>
      _subscriptionManager.batchSubscribe(subscriptions);
  
  /// Unsubscribe from a resource
  void unsubscribe(String resource, {String? id}) =>
      _subscriptionManager.unsubscribe(resource, id: id);
  
  /// Unsubscribe from an event type
  void unsubscribeFromEvent(String eventType) =>
      _subscriptionManager.unsubscribeFromEvent(eventType);
  
  /// Clean up all active subscriptions - call this in dispose()
  void cleanupSubscriptions() =>
      _subscriptionManager.cleanupSubscriptions();
  
  /// Add event listener
  void on(String eventName, Function(dynamic) handler) =>
      _subscriptionManager.on(eventName, handler);
  
  /// Remove event listener
  void off(String eventName, [Function(dynamic)? handler]) =>
      _subscriptionManager.off(eventName, handler);
  
  @override
  void dispose() {
    cleanupSubscriptions();
    super.dispose();
  }
}
