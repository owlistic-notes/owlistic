import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:provider/provider.dart';
import '../core/providers.dart';
import '../services/websocket_service.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../utils/logger.dart';
import '../services/app_state_service.dart';
import '../viewmodel/auth_viewmodel.dart';

class AuthProvider with ChangeNotifier implements AuthViewModel {
  String? _token;
  bool _isLoggedIn = false;
  bool _isLoading = false;
  bool _isActive = false;
  User? _currentUser;
  bool _isInitialized = false;
  String? _errorMessage;
  
  final Logger _logger = Logger('AuthProvider');
  final AuthService _authService;
  final AppStateService _appStateService;
  
  // Add stream controller for auth state changes
  final StreamController<bool> _authStateController = StreamController<bool>.broadcast();
  
  // Expose the stream
  @override
  Stream<bool> get authStateChanges => _authStateController.stream;
  
  @override
  String? get token => _token;
  
  // Constructor with dependency injection
  AuthProvider({
    required AuthService authService,
    AppStateService? appStateService
  }) : _authService = authService,
       _appStateService = appStateService ?? AppStateService() {
    try {
      _initializeAuthState();
      _isInitialized = true;
    } catch (e) {
      _logger.error('Error initializing auth state', e);
      _errorMessage = 'Failed to initialize: ${e.toString()}';
    }
  }
  
  // BaseViewModel implementation
  @override
  bool get isLoading => _isLoading;
  
  @override
  bool get isInitialized => _isInitialized;
  
  @override
  bool get isActive => _isActive;
  
  @override
  String? get errorMessage => _errorMessage;
  
  @override
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
  
  // AuthViewModel implementation
  @override
  bool get isLoggedIn => _isLoggedIn;
  
  @override
  User? get currentUser => _currentUser;
  
  Future<void> _initializeAuthState() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Ensure AuthService is initialized
      if (!_authService.isInitialized) {
        _logger.info('Waiting for AuthService initialization');
        await (_authService as dynamic).initialize();
      }
      
      // Load token from secure storage
      _token = await _authService.getStoredToken();
      
      if (_token != null && isTokenValid(_token!)) {
        // If token exists and is valid, set logged in state
        _isLoggedIn = true;
        _currentUser = await _authService.getUserProfile();
        _logger.info('Auth initialized with valid token for user: ${_currentUser?.email}');
      } else if (_token != null) {
        // If token exists but is invalid (expired), clean up
        await _authService.clearToken();
        _token = null;
        _isLoggedIn = false;
        _currentUser = null;
        _logger.info('Auth initialized with expired token - cleared');
      } else {
        // No token found
        _isLoggedIn = false;
        _logger.info('Auth initialized with no token');
      }
      
      // Emit initial auth state after determining isLoggedIn
      // Add try/catch to handle any potential errors
      try {
        _authStateController.add(_isLoggedIn);
      } catch (e) {
        _logger.error('Error emitting initial auth state', e);
      }
      
    } catch (e) {
      _logger.error('Error initializing auth state', e);
      _isLoggedIn = false;
      _errorMessage = e.toString();
      
      // Still emit initial auth state even after error
      try {
        _authStateController.add(false);
      } catch (e) {
        _logger.error('Error emitting initial auth state after error', e);
      }
    } finally {
      _isLoading = false;
      notifyListeners();
      
      // Notify auth state via service
      _appStateService.setAuthState(_isLoggedIn);
    }
  }

  // Check if token is valid (not expired)
  @override
  bool isTokenValid(String token) {
    try {
      // Check if token is expired
      return !JwtDecoder.isExpired(token);
    } catch (e) {
      _logger.error('Error validating token', e);
      return false;
    }
  }

  // Use AuthService for all authentication operations
  @override
  Future<bool> login(String email, String password, bool rememberMe) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      // Ensure AuthService is initialized before login
      if (!_authService.isInitialized) {
        _logger.info('Initializing AuthService before login');
        await (_authService as dynamic).initialize();
      }
      
      final response = await _authService.login(email, password);
      
      if (response['success'] ?? true) {
        _token = await _authService.getStoredToken();
        _isLoggedIn = true;
        _currentUser = await _authService.getUserProfile();
        _isLoading = false;
        
        _logger.info('Login successful for user: ${_currentUser?.email}');
        notifyListeners();
        
        // Broadcast auth state change via service
        _appStateService.setAuthState(_isLoggedIn);
        
        // Get WebSocketService from ServiceLocator directly
        final webSocketService = WebSocketService();
        webSocketService.setAuthToken(_token); // Set token first - primary authentication method
        
        // Also set user ID for any remaining legacy server-side features
        if (_currentUser != null) {
          webSocketService.setUserId(_currentUser!.id);
        }
        
        // Emit auth state change with error handling
        try {
          _authStateController.add(true);
        } catch (e) {
          _logger.error('Error emitting auth state change on login', e);
        }
        
        return true;
      } else {
        _errorMessage = "Invalid email or password";
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _logger.error('Login error', e);
      _errorMessage = e.toString();
      _isLoggedIn = false;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  @override
  Future<bool> register(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      final success = await _authService.register(email, password);
      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _logger.error('Registration error', e);
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  @override
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Broadcast app-wide reset event BEFORE clearing auth state
      _appStateService.resetAppState();
      
      // Perform logout with auth service
      await _authService.logout();
      
      // Clear local auth state
      _token = null;
      _isLoggedIn = false;
      _currentUser = null;
      
      // Get WebSocketService directly 
      final webSocketService = WebSocketService();
      webSocketService.clearState();
      
      _logger.info('User logged out successfully');
    } catch (e) {
      _logger.error('Logout error', e);
      // Even if there's an error, clear the local state
      _token = null;
      _isLoggedIn = false;
      _currentUser = null;
    } finally {
      _isLoading = false;
      notifyListeners();
      
      // Broadcast auth state change via service
      _appStateService.setAuthState(false);
      
      // Emit auth state change
      _authStateController.add(false);
    }
  }
  
  // BaseViewModel implementation
  @override
  void activate() {
    _isActive = true;
    _logger.info('AuthProvider activated');
    notifyListeners();
  }
  
  @override
  void deactivate() {
    _isActive = false;
    _logger.info('AuthProvider deactivated');
    notifyListeners();
  }
  
  @override
  void resetState() {
    _token = null;
    _isLoggedIn = false;
    _currentUser = null;
    _errorMessage = null;
    notifyListeners();
  }
  
  @override
  void dispose() {
    try {
      _authStateController.close();
    } catch (e) {
      _logger.error('Error closing auth state controller', e);
    }
    super.dispose();
  }
}
