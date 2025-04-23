import 'dart:async';
import '../utils/logger.dart';

/// Service for handling application-wide state changes and cross-provider communication
class AppStateService {
  static final AppStateService _instance = AppStateService._internal();
  final Logger _logger = Logger('AppStateService');
  
  // Stream controllers for different app events
  final StreamController<void> _resetStateController = StreamController<void>.broadcast();
  final StreamController<bool> _authStateController = StreamController<bool>.broadcast();

  // Private constructor
  AppStateService._internal();
  
  // Factory constructor to return the same instance
  factory AppStateService() {
    return _instance;
  }
  
  // Streams that providers can listen to
  Stream<void> get onResetState => _resetStateController.stream;
  Stream<bool> get onAuthStateChanged => _authStateController.stream;
  
  // Trigger app reset (when user logs out)
  void resetAppState() {
    _logger.info('Broadcasting app state reset event');
    _resetStateController.add(null);
  }
  
  // Broadcast auth state changes
  void setAuthState(bool isLoggedIn) {
    _logger.info('Broadcasting auth state change: isLoggedIn=$isLoggedIn');
    _authStateController.add(isLoggedIn);
  }
  
  // Clean up resources
  void dispose() {
    _resetStateController.close();
    _authStateController.close();
    _logger.info('AppStateService disposed');
  }
}
