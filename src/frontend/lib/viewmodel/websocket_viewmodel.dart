import 'dart:async';
import '../models/subscription.dart';
import '../models/user.dart';
import 'base_viewmodel.dart';

abstract class WebSocketViewModel extends BaseViewModel {
  // Connection state
  bool get isConnected;
  Future<bool> ensureConnected();
  Future<bool> reconnect();
  void disconnect();
  
  // Subscription management
  Future<void> subscribe(String resource, {String? id});
  Future<void> subscribeToEvent(String eventType);
  void unsubscribe(String resource, {String? id});
  void unsubscribeFromEvent(String eventType);
  Future<void> batchSubscribe(List<Subscription> subscriptions);
  bool isSubscribed(String resource, {String? id});
  bool isSubscribedToEvent(String eventType);
  
  // Event registration
  void addEventListener(String type, String event, Function(Map<String, dynamic>) handler);
  void removeEventListener(String type, String event);
  
  // Simple event listeners
  void on(String eventName, Function(dynamic) callback);
  void off(String eventName, [Function(dynamic)? callback]);
  
  // Stream access for reactive components
  Stream<Map<String, dynamic>> get messageStream;
  
  // Subscription tracking
  Set<String> get confirmedSubscriptions;
  Set<String> get pendingSubscriptions;
  int get totalSubscriptions;
  
  // Debug info
  User? get currentUser;
  String get lastEventType;
  String get lastEventAction;
  DateTime? get lastEventTime;
  int get messageCount;
  Map<String, dynamic> getDebugInfo();
  
  // Auth cleanup
  void clearAllSubscriptions();
  void clearOnLogout();
}
