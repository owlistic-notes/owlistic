import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/base_service.dart';
import '../utils/logger.dart';
import 'websocket_provider.dart';
import 'notes_provider.dart';
import 'notebooks_provider.dart';
import 'tasks_provider.dart';
import 'block_provider.dart';
import 'trash_provider.dart';

class AuthProvider with ChangeNotifier {
  String? _token;
  bool _isLoggedIn = false;
  bool _isLoading = false;
  User? _currentUser;
  String? _error;
  
  final Logger _logger = Logger('AuthProvider');
  final AuthService _authService;
  
  // Add a stream controller for auth state changes
  final StreamController<bool> _authStateController = StreamController<bool>.broadcast();
  Stream<bool> get authStateStream => _authStateController.stream;
  
  // References to providers that need cleanup on logout
  WebSocketProvider? _webSocketProvider;
  NotesProvider? _notesProvider;
  NotebooksProvider? _notebooksProvider;
  TasksProvider? _tasksProvider;
  BlockProvider? _blockProvider;
  TrashProvider? _trashProvider;
  
  // Constructor with dependency injection
  AuthProvider({AuthService? authService}) 
    : _authService = authService ?? ServiceLocator.get<AuthService>() {
    try {
      _initializeAuthState();
    } catch (e) {
      _logger.error('Error initializing auth state', e);
    }
  }
  
  // Getters
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  User? get currentUser => _currentUser;
  String? get error => _error;
  
  // Set references to providers for cleanup
  void setProviders({
    WebSocketProvider? webSocketProvider,
    NotesProvider? notesProvider,
    NotebooksProvider? notebooksProvider,
    TasksProvider? tasksProvider,
    BlockProvider? blockProvider,
    TrashProvider? trashProvider,
  }) {
    _webSocketProvider = webSocketProvider;
    _notesProvider = notesProvider;
    _notebooksProvider = notebooksProvider;
    _tasksProvider = tasksProvider;
    _blockProvider = blockProvider;
    _trashProvider = trashProvider;
  }
  
  Future<void> _initializeAuthState() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Load token from storage
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
    } catch (e) {
      _logger.error('Error initializing auth state', e);
      _isLoggedIn = false;
    } finally {
      _isLoading = false;
      notifyListeners();
      
      // Notify auth state stream about current state
      _authStateController.add(_isLoggedIn);
    }
  }

  // Check if token is valid (not expired)
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
  Future<bool> login(String email, String password, bool rememberMe) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final response = await _authService.login(email, password);
      
      if (response['success'] ?? true) {
        _token = await _authService.getStoredToken();
        _isLoggedIn = true;
        _currentUser = await _authService.getUserProfile();
        
        // Activate required providers immediately after login
        if (_notebooksProvider != null) {
          _logger.info('Activating NotebooksProvider after login');
          _notebooksProvider!.activate();
        }
        
        if (_notesProvider != null) {
          _logger.info('Activating NotesProvider after login');
          _notesProvider!.activate();
        }
        
        _isLoading = false;
        
        _logger.info('Login successful for user: ${_currentUser?.email}');
        notifyListeners();
        
        // Broadcast auth state change
        _authStateController.add(_isLoggedIn);
        
        return true;
      } else {
        _error = "Invalid email or password";
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _logger.error('Login error', e);
      _error = e.toString();
      _isLoggedIn = false;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  Future<bool> register(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final success = await _authService.register(email, password);
      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _logger.error('Registration error', e);
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  // Clear all provider data on logout
  void _clearProviderData() {
    _logger.info('Clearing all provider data on logout');
    
    // Clear WebSocket provider state and disconnect
    if (_webSocketProvider != null) {
      _webSocketProvider!.clearOnLogout();
    }
    
    // Reset all providers' data
    if (_notesProvider != null) {
      _notesProvider!.resetState();
    }
    
    if (_notebooksProvider != null) {
      _notebooksProvider!.resetState();
    }
    
    if (_tasksProvider != null) {
      _tasksProvider!.resetState();
    }
    
    if (_blockProvider != null) {
      _blockProvider!.resetState();
    }
    
    if (_trashProvider != null) {
      _trashProvider!.resetState();
    }
  }
  
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Clear all provider data before logging out
      _clearProviderData();
      
      // Perform logout with auth service
      await _authService.logout();
      
      // Clear local auth state
      _token = null;
      _isLoggedIn = false;
      _currentUser = null;
      
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
      
      // Broadcast auth state change
      _authStateController.add(false);
    }
  }
  
  void clearError() {
    _error = null;
    notifyListeners();
  }
  
  // Make sure dispose method properly cleans up
  @override
  void dispose() {
    _authStateController.close();
    super.dispose();
  }
}
