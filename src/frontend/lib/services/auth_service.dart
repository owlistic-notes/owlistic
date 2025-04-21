import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../utils/logger.dart';
import 'base_service.dart';

class AuthService extends BaseService {
  final Logger _logger = Logger('AuthService');
  static const String TOKEN_KEY = 'auth_token';
  
  // Properties needed by WebSocketProvider
  Stream<bool>? get authStateStream => null; // Stream of auth state changes
  bool get isLoggedIn => false; // Whether user is logged in
  
  // Authentication methods
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      // Not using authenticatedPost here since we don't have a token yet
      final response = await createPostRequest(
        '/api/v1/auth/login',
        {
          'email': email,
          'password': password,
        }
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _storeToken(data['token']); // Store the token
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
  
  // Helper method for unauthenticated POST (used for login/register)
  Future<http.Response> createPostRequest(String path, dynamic body) async {
    final uri = createUri(path);
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
      final response = await authenticatedPost(
        '/api/v1/auth/logout',
        {}
      );
      
      // Clear token regardless of response status
      await clearToken();
      
      _logger.info('Logged out successfully');
      return true;
    } catch (e) {
      _logger.error('Error during logout', e);
      // Still clear token on error
      await clearToken();
      return false;
    }
  }
  
  // Token management
  Future<String?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(TOKEN_KEY);
    if (token != null && token.isNotEmpty) {
      _logger.debug('Retrieved token from storage');
      // Also update the BaseService token
      await onTokenChanged(token);
    } else {
      _logger.debug('No token found in storage');
    }
    return token;
  }
  
  Future<void> _storeToken(String token) async {
    _logger.debug('Storing new auth token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(TOKEN_KEY, token);
    await onTokenChanged(token);
  }
  
  Future<void> clearToken() async {
    _logger.debug('Clearing auth token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(TOKEN_KEY);
    await onTokenChanged(null);
  }
  
  // This will be called when token changes
  Future<void> onTokenChanged(String? token) async {
    _logger.debug('Notifying token change: ${token != null ? 'Token present' : 'Token cleared'}');
    // Override in base_service to update global token
    notifyTokenChange(token);
  }
  
  Future<User?> getUserProfile() async {
    String? token = await getStoredToken();
    if (token == null) return null;
    
    try {
      // Extract user information from token
      final tokenParts = token.split('.');
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
  
  Future<bool> changePassword(String currentPassword, String newPassword) async {
    try {
      final response = await http.put(
        createUri('/api/v1/auth/password'),
        headers: getAuthHeaders(),
        body: jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      _logger.error('Error changing password', e);
      return false;
    }
  }
}
