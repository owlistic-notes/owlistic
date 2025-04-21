import 'dart:async';
import 'package:flutter/material.dart';
import '../providers/notes_provider.dart';
import '../providers/notebooks_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/block_provider.dart';
import '../utils/logger.dart';
import '../models/subscription.dart';
import '../providers/websocket_provider.dart';

/// Coordinates WebSocket events and manages subscriptions
class WebSocketEventCoordinator {
  final WebSocketProvider _webSocketProvider;
  final Logger _logger = Logger('WebSocketEventCoordinator');
  
  // Track active subscriptions
  final Set<Subscription> _activeSubscriptions = {};
  
  WebSocketEventCoordinator(this._webSocketProvider);
  
  // Subscribe to a resource
  Future<void> subscribe(String resource, {String? id}) async {
    final subscription = Subscription(resource: resource, id: id);
    
    if (!_activeSubscriptions.contains(subscription)) {
      _activeSubscriptions.add(subscription);
      await _webSocketProvider.subscribe(resource, id: id);
      _logger.debug('Subscribed to $subscription');
    }
  }
  
  // Subscribe to multiple resources at once
  Future<void> batchSubscribe(List<Subscription> subscriptions) async {
    final newSubscriptions = <Subscription>[];
    
    for (final subscription in subscriptions) {
      if (!_activeSubscriptions.contains(subscription)) {
        _activeSubscriptions.add(subscription);
        newSubscriptions.add(subscription);
      }
    }
    
    if (newSubscriptions.isNotEmpty) {
      await _webSocketProvider.batchSubscribe(newSubscriptions);
      _logger.debug('Batch subscribed to ${newSubscriptions.length} resources');
    }
  }
  
  // Unsubscribe from a resource
  void unsubscribe(String resource, {String? id}) {
    final subscription = Subscription(resource: resource, id: id);
    
    if (_activeSubscriptions.contains(subscription)) {
      _activeSubscriptions.remove(subscription);
      _webSocketProvider.unsubscribe(resource, id: id);
      _logger.debug('Unsubscribed from $subscription');
    }
  }
  
  // Unsubscribe from all active subscriptions
  void unsubscribeAll() {
    for (final subscription in _activeSubscriptions) {
      _webSocketProvider.unsubscribe(
        subscription.resource,
        id: subscription.id,
      );
    }
    
    _logger.debug('Unsubscribed from all ${_activeSubscriptions.length} resources');
    _activeSubscriptions.clear();
  }
  
  // Add event listener for a specific event
  void on(String eventName, Function(dynamic) handler) {
    _webSocketProvider.on(eventName, handler);
  }
  
  // Remove event listener
  void off(String eventName, [Function(dynamic)? handler]) {
    _webSocketProvider.off(eventName, handler);
  }
}
