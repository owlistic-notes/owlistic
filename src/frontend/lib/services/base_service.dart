import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

// Service locator for dependency injection
class ServiceLocator {
  static final Map<Type, dynamic> _services = {};

  static void register<T>(T service) {
    _services[T] = service;
  }

  static T get<T>() {
    if (!_services.containsKey(T)) {
      throw Exception('Service of type $T not registered');
    }
    return _services[T];
  }
}

// Base class for all API services
class BaseService {
  static String? _token;
  final Logger _logger = Logger('BaseService');
  static const String TOKEN_KEY = 'auth_token';
  
  // Stream controllers for auth state changes
  static final _authStateController = StreamController<bool>.broadcast();
  Stream<bool> get authStateChanges => _authStateController.stream;
  
  BaseService() {
    // Try to load token on initialization
    _loadTokenFromStorage();
  }
  
  // Load token from storage when service is initialized
  Future<void> _loadTokenFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(TOKEN_KEY);
      _logger.debug('Loaded auth token from storage: ${_token != null ? 'Present' : 'Not found'}');
    } catch (e) {
      _logger.error('Error loading token from storage', e);
    }
  }
  
  // Update token when it changes
  void notifyTokenChange(String? token) {
    _token = token;
    _logger.debug('Auth token updated: ${_token != null ? 'Present' : 'Cleared'}');
    _authStateController.add(_token != null);
  }

  // Base URL from environment
  String get baseApiUrl {
    return dotenv.env['API_URL'] ?? 'http://localhost:8080';
  }
  
  // Create URI for API endpoints with proper query parameter handling
  Uri createUri(String path, {Map<String, dynamic>? queryParameters}) {
    final uri = Uri.parse('$baseApiUrl$path');

    if (queryParameters != null && queryParameters.isNotEmpty) {
      // Convert all values to strings for proper URL encoding
      final stringParams = queryParameters.map((key, value) => 
        MapEntry(key, value?.toString() ?? ''));
      
      return uri.replace(queryParameters: stringParams);
    }
    
    return uri;
  }

  // Get headers including auth token if available
  Map<String, String> getBaseHeaders() {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }
  
  // Get authenticated headers - ALWAYS include the token if available
  Map<String, String> getAuthHeaders() {
    final headers = getBaseHeaders();
    
    if (_token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_token';
      _logger.debug('Added auth token to request headers');
    } else {
      _logger.warning('No auth token available for authenticated request');
    }
    
    return headers;
  }
  
  // Helper method for authenticated GET requests
  Future<http.Response> authenticatedGet(String path, {Map<String, dynamic>? queryParams}) async {
    final uri = createUri(path, queryParameters: queryParams);
    _logger.debug('Making authenticated GET request to: $uri');
    
    // Always use auth headers for authenticated requests
    final response = await http.get(
      uri,
      headers: getAuthHeaders(),
    );
    
    _handleResponseStatus(response);
    return response;
  }
  
  // Helper method for authenticated POST requests
  Future<http.Response> authenticatedPost(String path, dynamic body) async {
    final uri = createUri(path);
    _logger.debug('Making authenticated POST request to: $uri');
    
    final response = await http.post(
      uri,
      headers: getAuthHeaders(),
      body: jsonEncode(body),
    );
    
    _handleResponseStatus(response);
    return response;
  }
  
  // Helper method for authenticated PUT requests
  Future<http.Response> authenticatedPut(String path, dynamic body) async {
    final uri = createUri(path);
    _logger.debug('Making authenticated PUT request to: $uri');
    
    final response = await http.put(
      uri,
      headers: getAuthHeaders(),
      body: jsonEncode(body),
    );
    
    _handleResponseStatus(response);
    return response;
  }
  
  // Helper method for authenticated DELETE requests
  Future<http.Response> authenticatedDelete(String path) async {
    final uri = createUri(path);
    _logger.debug('Making authenticated DELETE request to: $uri');
    
    final response = await http.delete(
      uri,
      headers: getAuthHeaders(),
    );
    
    _handleResponseStatus(response);
    return response;
  }
  
  // Handle response status and log accordingly
  void _handleResponseStatus(http.Response response) {
    final statusCode = response.statusCode;
    final requestUrl = response.request?.url.toString() ?? 'unknown';
    
    if (statusCode >= 200 && statusCode < 300) {
      _logger.debug('Request successful: $requestUrl (status: $statusCode)');
    } else {
      _logger.error('Request failed: $requestUrl (status: $statusCode), body: ${response.body}');
      
      // Handle authentication errors
      if (statusCode == 401) {
        _logger.warning('Authentication error - token might be invalid or expired');
      }
    }
  }
}
