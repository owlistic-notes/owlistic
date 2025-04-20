import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../utils/logger.dart';

class AuthProvider with ChangeNotifier implements Listenable {
  final Logger _logger = Logger('AuthProvider');
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  User? _currentUser;
  String? _token;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  bool _initialized = false;
  
  // Getters
  User? get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get token => _token;
  bool get initialized => _initialized;
  
  // Initialize auth state from secure storage
  Future<void> initialize() async {
    if (_initialized) return;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      // Check if we have a token stored
      final storedToken = await _storage.read(key: 'auth_token');
      if (storedToken != null) {
        _token = storedToken;
        ApiService.setToken(storedToken);
        
        // Get user immediately from the API service
        _currentUser = ApiService.getCurrentUser();
        
        if (_currentUser != null) {
          _isAuthenticated = true;
          _logger.info('User authenticated from stored token: ${_currentUser!.id}');
        } else {
          // Token is invalid, clear storage
          await _storage.delete(key: 'auth_token');
          _token = null;
          _isAuthenticated = false;
          _logger.info('Stored token was invalid');
        }
      }
    } catch (e) {
      _logger.error('Error initializing auth state', e);
      _isAuthenticated = false;
      _token = null;
      await _storage.delete(key: 'auth_token');
    } finally {
      _initialized = true;
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Login with email and password
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _logger.info('Attempting login for user: $email');
      final response = await ApiService.login(email, password);
      _token = response['token'];
      
      _logger.info('Login successful, token received');
      
      // Store token in API service
      ApiService.setToken(_token!);
      
      // Store token in secure storage
      await _storage.write(key: 'auth_token', value: _token);
      
      // Get user profile from token
      _currentUser = ApiService.getCurrentUser();
      
      if (_currentUser == null) {
        _logger.error('Failed to parse user profile from token');
        _isLoading = false;
        _isAuthenticated = false;
        notifyListeners();
        return false;
      }
      
      _logger.info('User profile extracted: ${_currentUser!.email} with ID: ${_currentUser!.id}');
      _isAuthenticated = true;
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _logger.error('Login failed', e);
      _isLoading = false;
      _isAuthenticated = false;
      notifyListeners();
      return false;
    }
  }
  
  // Register new user
  Future<bool> register(String email, String password, String confirmPassword) async {
    // Validate passwords match
    if (password != confirmPassword) {
      _logger.error('Passwords do not match');
      return false;
    }
    
    _isLoading = true;
    notifyListeners();
    
    try {
      final user = await ApiService.register(email, password);
      
      // Automatically log in after registration
      return await login(email, password);
    } catch (e) {
      _logger.error('Registration failed', e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  // Logout
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Clear token from secure storage
      await _storage.delete(key: 'auth_token');
      
      // Clear token from API service
      ApiService.clearToken();
      
      _token = null;
      _currentUser = null;
      _isAuthenticated = false;
      
      _logger.info('User logged out');
    } catch (e) {
      _logger.error('Logout failed', e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Update user profile
  Future<bool> updateProfile(Map<String, dynamic> data) async {
    if (!_isAuthenticated || _currentUser == null) {
      return false;
    }
    
    _isLoading = true;
    notifyListeners();
    
    try {
      final updatedUser = await ApiService.updateUserProfile(data);
      _currentUser = updatedUser;
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _logger.error('Profile update failed', e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  // Change password
  Future<bool> changePassword(String currentPassword, String newPassword) async {
    if (!_isAuthenticated) {
      return false;
    }
    
    _isLoading = true;
    notifyListeners();
    
    try {
      final success = await ApiService.changePassword(
        currentPassword, 
        newPassword
      );
      
      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _logger.error('Password change failed', e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
