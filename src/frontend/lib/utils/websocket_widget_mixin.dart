import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/websocket_provider.dart';
import 'websocket_event_coordinator.dart';
import 'logger.dart';

/// A mixin for widgets that need to subscribe to WebSocket events
mixin WebSocketWidgetMixin<T extends StatefulWidget> on State<T> {
  /// WebSocket event coordinator
  late final WebSocketEventCoordinator _coordinator;
  final Logger _logger = Logger('WebSocketWidgetMixin');
  bool _initialized = false;
  
  /// Access to the coordinator for subclasses
  WebSocketEventCoordinator get coordinator => _coordinator;
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Initialize coordinator only once
    if (!_initialized) {
      _initialized = true;
      _logger.debug("Initializing WebSocketEventCoordinator");
      
      // Get the WebSocketProvider from the widget tree
      final webSocketProvider = Provider.of<WebSocketProvider>(context, listen: false);
      _coordinator = WebSocketEventCoordinator(webSocketProvider);
      
      // Set up subscriptions
      _logger.debug("Setting up WebSocket subscriptions");
      setupWebSocketSubscriptions();
    }
  }
  
  /// Override this method to set up WebSocket subscriptions
  void setupWebSocketSubscriptions() {
    // Implement in subclass
  }
  
  @override
  void dispose() {
    // Clean up WebSocket subscriptions and event listeners
    _logger.debug("Disposing WebSocketWidgetMixin resources");
    _coordinator.unsubscribeAll();
    _initialized = false;
    super.dispose();
  }
}
