import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

// Enhanced version of BaseService with better error handling and validation
abstract class BaseService {
  static String? _token;
  static String _baseUrl = '';
  static final Logger _logger = Logger('BaseService');
  static const String TOKEN_KEY = 'auth_token';
  
  // Stream controllers for auth state changes
  static final _authStateController = StreamController<bool>.broadcast();
  Stream<bool> get authStateChanges => _authStateController.stream;
  
  // Initialize with environment configuration
  BaseService() {
    _baseUrl = dotenv.env['API_URL'] ?? '';
    if (_baseUrl.isEmpty) {
      _logger.warning('API_URL environment variable not set. Using default empty base URL.');
    }
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
  static void notifyTokenChange(String? token) {
    _token = token;
    _logger.debug('Auth token updated: ${_token != null ? 'Present' : 'Cleared'}');
    _authStateController.add(_token != null);
  }

  // Create URIs with proper encoding of parameters
  Uri createUri(String path, {Map<String, dynamic>? queryParameters}) {
    // Validate path
    if (!path.startsWith('/')) {
      path = '/' + path;
    }
    
    // Handle empty base URL
    String fullUrl = _baseUrl.isEmpty 
        ? 'http://localhost:8080$path'  // Default fallback
        : _baseUrl + path;
    
    // Convert all query parameter values to strings
    Map<String, String>? stringParams;
    if (queryParameters != null) {
      stringParams = {};
      queryParameters.forEach((key, value) {
        if (value != null) {
          stringParams![key] = value.toString();
        }
      });
    }
    
    return Uri.parse(fullUrl).replace(queryParameters: stringParams);
  }

  // Get authorization headers
  Map<String, String> getBaseHeaders() {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }
  
  Map<String, String> getAuthHeaders() {
    final headers = getBaseHeaders();
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  // Helper methods for API calls with better error handling
  Future<http.Response> authenticatedGet(String path, {Map<String, dynamic>? queryParameters}) async {
    final uri = createUri(path, queryParameters: queryParameters);
    _logger.debug('GET: $uri');
    
    try {
      final response = await http.get(uri, headers: getAuthHeaders());
      _validateResponse(response, 'GET', uri.toString());
      return response;
    } catch (e) {
      _logger.error('HTTP GET error: $path', e);
      rethrow;
    }
  }

  Future<http.Response> authenticatedPost(String path, dynamic body) async {
    final uri = createUri(path);
    _logger.debug('POST: $uri');
    
    try {
      final bodyJson = jsonEncode(body);
      final response = await http.post(
        uri,
        headers: getAuthHeaders(),
        body: bodyJson,
      );
      _validateResponse(response, 'POST', uri.toString(), body: body);
      return response;
    } catch (e) {
      _logger.error('HTTP POST error: $path', e);
      rethrow;
    }
  }

  Future<http.Response> authenticatedPut(String path, dynamic body) async {
    final uri = createUri(path);
    _logger.debug('PUT: $uri');
    
    try {
      final response = await http.put(
        uri,
        headers: getAuthHeaders(),
        body: jsonEncode(body),
      );
      _validateResponse(response, 'PUT', uri.toString(), body: body);
      return response;
    } catch (e) {
      _logger.error('HTTP PUT error: $path', e);
      rethrow;
    }
  }

  Future<http.Response> authenticatedDelete(String path) async {
    final uri = createUri(path);
    _logger.debug('DELETE: $uri');
    
    try {
      final response = await http.delete(uri, headers: getAuthHeaders());
      _validateResponse(response, 'DELETE', uri.toString());
      return response;
    } catch (e) {
      _logger.error('HTTP DELETE error: $path', e);
      rethrow;
    }
  }
  
  // Validate HTTP responses
  void _validateResponse(http.Response response, String method, String url, {dynamic body}) {
    bool isSuccess = response.statusCode >= 200 && response.statusCode < 300;
    
    if (!isSuccess) {
      _logger.error(
        'HTTP $method failed: $url\nStatus: ${response.statusCode}\nResponse: ${response.body}',
      );
      
      if (kDebugMode && body != null) {
        _logger.debug('Request body: ${jsonEncode(body)}');
      }
    }
  }
  
  // Validate IDs to prevent empty or malformed IDs
  bool isValidId(String? id) {
    return id != null && id.isNotEmpty;
  }
  
  // Validate required string parameters
  void validateRequiredParam(String? value, String paramName) {
    if (value == null || value.isEmpty) {
      throw ArgumentError('$paramName cannot be null or empty');
    }
  }
}

// ServiceLocator for DI support
class ServiceLocator {
  static final Map<Type, Object> _services = {};
  
  static void register<T>(T service) {
    _services[T] = service!;
  }
  
  static T get<T>() {
    if (_services.containsKey(T)) {
      return _services[T] as T;
    }
    throw Exception('Service $T not registered');
  }
}
