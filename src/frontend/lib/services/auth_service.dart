import 'dart:convert';
import 'dart:async';
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
  
  // Constructor sets the instance for static access
  AuthService() {
    _instance = this;
  }
  
  bool get isLoggedIn => _token != null;
  
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
        await _storeToken(data['token']);
        return data;
      } else {
        _logger.error('Login failed with status: ${response.statusCode}');
        throw Exception('Failed to login: ${response.body}');
      }
    } catch (e) {
      _logger.error('Error during login', e);
      throw e;
    }
  }
  
  // Helper method for unauthenticated POST
  Future<http.Response> createPostRequest(String path, dynamic body) async {
    final uri = createUri(path);
    return http.post(
      uri,
      headers: getBaseHeaders(), // Use base headers for unauthenticated requests
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
        _logger.error('Registration failed with status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      _logger.error('Error during registration', e);
      return false;
    }
  }
  
  Future<bool> logout() async {
    try {
      // Call logout endpoint if it exists
      if (isLoggedIn) {
        await authenticatedPost('/api/v1/auth/logout', {});
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
  
  // Token management
  Future<String?> getStoredToken() async {
    try {
      _token = await _secureStorage.read(key: tokenKey);
      if (_token != null && _token!.isNotEmpty) {
        _logger.debug('Retrieved token from storage');
        _authStateController.add(true);
      } else {
        _token = null;
        _logger.debug('No token found in storage');
      }
      return _token;
    } catch (e) {
      _logger.error('Error reading token from secure storage', e);
      return null;
    }
  }
  
  Future<void> _storeToken(String token) async {
    if (token.isEmpty) return;
    
    _token = token;
    _logger.debug('Storing auth token');
    
    try {
      await _secureStorage.write(key: tokenKey, value: token);
      _authStateController.add(true);
    } catch (e) {
      _logger.error('Error storing token in secure storage', e);
      rethrow;
    }
  }
  
  Future<void> clearToken() async {
    _token = null;
    _logger.debug('Clearing auth token');
    
    try {
      await _secureStorage.delete(key: tokenKey);
      _authStateController.add(false);
    } catch (e) {
      _logger.error('Error clearing token from secure storage', e);
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
      await getCurrentUser();
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
      
      // Fall back to getting user profile if needed
      final user = await getCurrentUser();
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
      return response.isNotEmpty;
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
