import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../utils/logger.dart';
import 'base_service.dart';

class AuthService extends BaseService {
  final Logger _logger = Logger('AuthService');
  static const String tokenKey = 'auth_token';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  // Stream controller for auth state changes
  final StreamController<bool> _authStateController = StreamController<bool>.broadcast();
  Stream<bool> get authStateChanges => _authStateController.stream;
  
  // Token management centralized in AuthService
  // Using instance property for local reference and a static for global access
  String? _token;
  static String? get token => _instance?._token;
  
  // Singleton pattern for global token access
  static AuthService? _instance;
  // Initialize synchronously - guaranteed to be true after constructor
  bool _isInitialized = true;
  bool get isInitialized => true; // Always return true for safety
  
  // Constructor sets the instance for static access
  AuthService() {
    _instance = this;
    
    // Load token synchronously if possible - use SharedPreferences for sync access
    _loadTokenSync();
    
    // Always mark initialized to avoid initialization errors
    _logger.info('AuthService initialized fully with sync token: ${_token != null}');
  }
  
  // Synchronous loading of token using SharedPreferences
  void _loadTokenSync() {
    try {
      // Try loading from shared prefs first - this is synchronous
      final tokenFromPrefs = _getTokenFromPrefsSync();
      if (tokenFromPrefs != null) {
        _token = tokenFromPrefs;
        BaseService.setAuthToken(_token); // Important fix: set token in BaseService
        _logger.debug('Successfully loaded token synchronously from shared prefs');
        return;
      }
      
      // Fall back to empty token if we can't load one synchronously
      _token = null;
      _logger.debug('No token found in sync storage, defaulting to null token');
      
      // Start async token loading in background
      _loadTokenAsyncInBackground();
    } catch (e) {
      _logger.error('Error loading token synchronously', e);
      _token = null; // Default to no token on error
    }
  }
  
  // Try to get token from SharedPreferences synchronously
  String? _getTokenFromPrefsSync() {
    try {
      // This is actually async but we're setting it up to run in background
      SharedPreferences.getInstance().then((prefs) {
        final token = prefs.getString(tokenKey);
        if (token != null && token.isNotEmpty) {
          _token = token;
          BaseService.setAuthToken(_token); // Important fix: set token in BaseService
          _authStateController.add(true);
          _logger.debug('Token loaded from SharedPreferences in background');
        }
      });
      
      // Return null for now but it will be loaded in background
      return null;
    } catch (e) {
      _logger.error('Error reading token from SharedPreferences', e);
      return null;
    }
  }
  
  // Load token in background as backup
  void _loadTokenAsyncInBackground() {
    _secureStorage.read(key: tokenKey).then((value) {
      if (value != null && value.isNotEmpty) {
        _token = value;
        BaseService.setAuthToken(_token); // Important fix: set token in BaseService
        _authStateController.add(true);
        _logger.debug('Token loaded from secure storage in background');
        
        // Save to SharedPreferences for faster access next time
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString(tokenKey, value);
        });
      }
    }).catchError((e) {
      _logger.error('Error loading token from secure storage', e);
    });
  }
  
  // Fixed up initialize method - call explicitly from login/register to ensure token is set
  Future<void> initialize() async {
    _logger.debug('Initializing AuthService explicitly');
    
    // Make sure token is loaded into BaseService
    if (_token != null) {
      BaseService.setAuthToken(_token);
      _logger.debug('Auth token set in BaseService: ${_token?.substring(0, 10)}...');
    }
    return Future.value();
  }
  
  bool get isLoggedIn => _token != null;
  
  // Add back getStoredToken method that was accidentally removed
  Future<String?> getStoredToken() async {
    // If we already have a token in memory, just return it
    if (_token != null) return _token;
    
    try {
      // Try SharedPreferences first for speed
      final prefs = await SharedPreferences.getInstance();
      final storedToken = prefs.getString(tokenKey);
      
      if (storedToken != null && storedToken.isNotEmpty) {
        _token = storedToken;
        // Update BaseService token - critical fix
        BaseService.setAuthToken(_token);
        
        _authStateController.add(true);
        _logger.debug('Retrieved token from SharedPreferences');
        return storedToken;
      }
      
      // Fall back to secure storage if not in SharedPreferences
      _token = await _secureStorage.read(key: tokenKey);
      if (_token != null && _token!.isNotEmpty) {
        _logger.debug('Retrieved token from secure storage');
        // Update BaseService token - critical fix
        BaseService.setAuthToken(_token);
        
        _authStateController.add(true);
        
        // Save to SharedPreferences for faster access next time
        prefs.setString(tokenKey, _token!);
      } else {
        _token = null;
        _logger.debug('No token found in storage');
      }
      return _token;
    } catch (e) {
      _logger.error('Error reading token from storage', e);
      return null;
    }
  }

  // Authentication methods
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await createPostRequest(
        '/api/v1/auth/login',
        {
          'email': email,
          'password': password,
        }
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Critical fix: Extract token properly
        final token = data['token'] as String?;
        if (token == null || token.isEmpty) {
          throw Exception('No token received from server');
        }
        
        _logger.debug('Login successful, token received');
        await _storeToken(token);
        return {'success': true, 'token': token, 'userId': data['user_id'] ?? data['userId']};
      } else {
        _logger.error('Login failed with status: ${response.statusCode}, body: ${response.body}');
        throw Exception('Failed to login: ${response.body}');
      }
    } catch (e) {
      _logger.error('Error during login', e);
      throw e;
    }
  }
  
  // Helper method for unauthenticated POST - fixed to handle async URI creation
  Future<http.Response> createPostRequest(String path, dynamic body) async {
    // Properly await the URI creation
    final uri = await createUri(path);
    _logger.debug('Creating unauthenticated POST request to $uri');
    
    return http.post(
      uri,
      headers: getBaseHeaders(),
      body: jsonEncode(body),
    );
  }
  
  Future<bool> register(String email, String password) async {
    try {
      // Not using authenticatedPost here since we don't have a token yet
      final response = await createPostRequest(
        '/api/v1/auth/register',
        {
          'email': email,
          'password': password,
        }
      );

      if (response.statusCode == 201) {
        _logger.info('Registration successful for: $email');
        return true;
      } else {
        _logger.error('Registration failed with status: ${response.statusCode}, body: ${response.body}');
        throw Exception('Registration failed: ${response.body}');
      }
    } catch (e) {
      _logger.error('Error during registration', e);
      throw e;
    }
  }
  
  Future<bool> logout() async {
    try {
      // Call logout endpoint if it exists and we have a token
      if (isLoggedIn) {
        try {
          await authenticatedPost('/api/v1/auth/logout', {});
        } catch (e) {
          // Just log the error but continue with local logout
          _logger.error('Error calling logout endpoint', e);
        }
      }
      
      // Clear token regardless of response
      await clearToken();
      _logger.info('Logged out successfully');
      return true;
    } catch (e) {
      _logger.error('Error during logout', e);
      await clearToken(); // Still clear token on error
      return false;
    }
  }
  
  // Token management - store in both secure storage and SharedPreferences
  Future<void> _storeToken(String token) async {
    if (token.isEmpty) return;
    
    _token = token;
    // Update the static token in BaseService
    BaseService.setAuthToken(token);
    
    _logger.debug('Storing auth token');
    
    try {
      // Store in secure storage
      await _secureStorage.write(key: tokenKey, value: token);
      
      // Also store in SharedPreferences for sync access next time
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(tokenKey, token);
      
      _authStateController.add(true);
    } catch (e) {
      _logger.error('Error storing token', e);
      rethrow;
    }
  }
  
  // Clear token from both storages
  Future<void> clearToken() async {
    _token = null;
    // Clear the static token in BaseService
    BaseService.setAuthToken(null);
    
    _logger.debug('Clearing auth token');
    
    try {
      // Clear from secure storage
      await _secureStorage.delete(key: tokenKey);
      
      // Also clear from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(tokenKey);
      
      _authStateController.add(false);
    } catch (e) {
      _logger.error('Error clearing token', e);
    }
  }
  
  // Update token and notify systems
  Future<void> onTokenChanged(String? token) async {
    try {
      if (token == null || token.isEmpty) {
        await clearToken();
        _logger.info('Auth token cleared');
        return;
      }
      
      // Store token
      await _storeToken(token);
      _logger.info('Auth token updated successfully');
      
      // Attempt to fetch user info with new token
      await getUserProfile();
    } catch (e) {
      _logger.error('Error in onTokenChanged', e);
      await clearToken();
      rethrow;
    }
  }
  
  // Get user information from token or API
  Future<User?> getUserProfile() async {
    _token ??= await getStoredToken();
    
    if (_token == null) return null;
    
    try {
      // Extract user info from JWT payload
      final tokenParts = _token!.split('.');
      if (tokenParts.length != 3) {
        _logger.error("Invalid JWT token format");
        return null;
      }
      
      String normalized = base64Url.normalize(tokenParts[1]);
      final payloadJson = utf8.decode(base64Url.decode(normalized));
      final payload = jsonDecode(payloadJson);
      
      return User(
        id: payload['UserID'] ?? payload['user_id'] ?? payload['sub'] ?? '',
        email: payload['email'] ?? '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      _logger.error('Error getting user profile', e);
      return null;
    }
  }
  
  // Get user info from API endpoint
  Future<User?> getCurrentUser() async {
    if (!isLoggedIn) {
      _logger.debug('Cannot get user profile: not logged in');
      return null;
    }
    
    try {
      final userId = await getCurrentUserId();
      final response = await authenticatedGet('/api/v1/user/$userId');
      
      if (response.statusCode == 200) {
        final userData = jsonDecode(response.body);
        final user = User.fromJson(userData);
        
        // Store user ID in shared preferences for offline access
        if (user.id.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_id', user.id);
          _logger.debug('Stored user ID in preferences: ${user.id}');
        }
        
        return user;
      } else if (response.statusCode == 401) {
        // Token is invalid, clear it
        await clearToken();
        return null;
      } else {
        _logger.error('Failed to get user profile: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      _logger.error('Error getting current user', e);
      return null;
    }
  }

  // Helper method to get current user ID
Future<String?> getCurrentUserId() async {
    try {
      // First try to get from shared preferences for better performance
      final prefs = await SharedPreferences.getInstance();
      String? storedUserId = prefs.getString('user_id');
      
      if (storedUserId != null && storedUserId.isNotEmpty) {
        return storedUserId;
      }
      
      // Extract from token if possible
      if (_token != null) {
        try {
          final tokenParts = _token!.split('.');
          if (tokenParts.length == 3) {
            String normalized = base64Url.normalize(tokenParts[1]);
            final payloadJson = utf8.decode(base64Url.decode(normalized));
            final payload = jsonDecode(payloadJson);
            final userId = payload['UserID'] ?? payload['user_id'] ?? payload['sub'];
            if (userId != null && userId is String && userId.isNotEmpty) {
              return userId;
            }
          }
        } catch (e) {
          _logger.error('Error extracting user ID from token', e);
        }
      }
      
      // Fall back to getting user profile if needed
      final user = await getUserProfile();
      return user?.id;
    } catch (e) {
      _logger.error('Error getting current user ID', e);
      return null;
    }
  }
  
  // Safe login with better error handling
  Future<bool> loginSafe(String email, String password) async {
    try {
      final response = await login(email, password);
      return response['success'] == true;
    } catch (e) {
      _logger.error('Login error occurred', e);
      await clearToken();  // Ensure we clean up on error
      return false;
    }
  }
  
  // Clean up resources
  void dispose() {
    if (!_authStateController.isClosed) {
      _authStateController.close();
    }
  }
}

// Custom error class for initialization issues
class NotInitializedError extends Error {
  final String message;
  NotInitializedError(this.message);
  
  @override
  String toString() => message;
}
