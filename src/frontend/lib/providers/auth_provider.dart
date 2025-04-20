import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../utils/logger.dart';

class AuthProvider extends ChangeNotifier {
  final Logger _logger = Logger('AuthProvider');
  
  bool _isLoggedIn = false;
  bool _isLoading = false;
  String? _error;
  User? _currentUser;
  String? _token;
  static const String TOKEN_KEY = 'auth_token';
  
  // Getters
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get errorMessage => _error;
  User? get currentUser => _currentUser;
  String? get token => _token;
  
  // Initialize provider state on startup
  AuthProvider() {
    _initializeAuthState();
  }
  
  Future<void> _initializeAuthState() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Check for existing token
      _token = await loadToken();
      
      if (_token != null && isTokenValid(_token!)) {
        _logger.info('Found valid token on startup');
        
        // Get user info from token
        final userInfo = getUserInfoFromToken();
        if (userInfo != null) {
          _isLoggedIn = true;
          _currentUser = User(
            id: userInfo['sub'] ?? userInfo['UserID'] ?? userInfo['userId'] ?? '',
            email: userInfo['email'] ?? '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          _logger.info('Successfully restored user session for: ${_currentUser?.email}');
        }
      } else {
        _logger.info('No valid token found on startup');
      }
    } catch (e) {
      _logger.error('Error initializing auth state', e);
      _error = "Session expired or invalid. Please login again.";
      await clearToken();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Load token from persistent storage
  Future<String?> loadToken() async {
    if (_token != null) return _token;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(TOKEN_KEY);
      return _token;
    } catch (e) {
      _logger.error('Failed to load token from storage', e);
      return null;
    }
  }

  // Save token to persistent storage
  Future<void> saveToken(String token) async {
    _token = token;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(TOKEN_KEY, token);
    } catch (e) {
      _logger.error('Failed to save token to storage', e);
    }
  }

  // Clear token from persistent storage
  Future<void> clearToken() async {
    _token = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(TOKEN_KEY);
    } catch (e) {
      _logger.error('Failed to clear token from storage', e);
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

  // Extract user info from token
  Map<String, dynamic>? getUserInfoFromToken() {
    if (_token == null) return null;
    
    try {
      // Decode token payload
      return JwtDecoder.decode(_token!);
    } catch (e) {
      _logger.error('Error decoding token', e);
      return null;
    }
  }
  
  Future<bool> login(String email, String password, bool rememberMe) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      _logger.info('Attempting to login: $email');
      final response = await ApiService.login(email, password, rememberMe);
      
      if (response) {
        // API Service has already saved the token, get it for our provider
        _token = await ApiService.getStoredToken();
        
        // Parse user data from token
        _isLoggedIn = true;
        final userInfo = getUserInfoFromToken();
        if (userInfo != null) {
          _currentUser = User(
            id: userInfo['sub'] ?? userInfo['UserID'] ?? userInfo['userId'] ?? '',
            email: userInfo['email'] ?? '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
        }
        
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = "Login failed";
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
      _logger.info('Attempting to register: $email');
      final response = await ApiService.register(email, password);
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _logger.error('Registration error', e);
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Call logout API endpoint
      await ApiService.logout();
      
      // Clear token from storage
      await clearToken();
      
      // Reset auth state
      _isLoggedIn = false;
      _currentUser = null;
    } catch (e) {
      _logger.error('Logout error', e);
      // Even if there's an error, we'll clear the local state
      await clearToken();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
