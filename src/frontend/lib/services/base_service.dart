import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../utils/logger.dart';

// Base service class with minimal responsibilities
abstract class BaseService {
  static final Logger _logger = Logger('BaseService');
  
  // Base URL from environment variables
  static String get _baseUrl => dotenv.env['API_URL'] ?? 'http://localhost:8080';
  
  // Static token accessor that can be set by AuthService
  static String? _authToken;
  
  // Setter for the auth token that AuthService can call
  static void setAuthToken(String? token) {
    _authToken = token;
  }
  
  // Getter for the auth token
  static String? get authToken => _authToken;
  
  // Create URI helper
  Uri createUri(String path, {Map<String, dynamic>? queryParameters}) {
    // Validate path
    if (!path.startsWith('/')) {
      path = '/' + path;
    }
    
    // Build full URL
    String fullUrl = _baseUrl + path;
    
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

  // Get base headers without auth
  Map<String, String> getBaseHeaders() {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }
  
  // Get auth headers without direct dependency on AuthService
  Map<String, String> getAuthHeaders() {
    final headers = getBaseHeaders();
    
    // Get token from static field instead of AuthService
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    
    return headers;
  }

  // Helper methods for API calls with better error handling
  Future<http.Response> authenticatedGet(String path, {Map<String, dynamic>? queryParameters}) async {
    final uri = createUri(path, queryParameters: queryParameters);
    _logger.debug('GET: $uri');
    
    try {
      // Always use getAuthHeaders to get the current token
      final response = await http.get(uri, headers: getAuthHeaders());
      _validateResponse(response, 'GET', uri.toString());
      return response;
    } catch (e) {
      _logger.error('HTTP GET error: $path', e);
      rethrow;
    }
  }

  Future<http.Response> authenticatedPost(String path, dynamic body, {Map<String, dynamic>? queryParameters}) async {
    final uri = createUri(path, queryParameters: queryParameters);
    _logger.debug('POST: $uri');
    
    try {
      final bodyJson = jsonEncode(body);
      // Always use getAuthHeaders to get the current token
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

  Future<http.Response> authenticatedPut(String path, dynamic body, {Map<String, dynamic>? queryParameters}) async {
    final uri = createUri(path, queryParameters: queryParameters);
    _logger.debug('PUT: $uri');
    
    try {
      // Always use getAuthHeaders to get the current token
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

  Future<http.Response> authenticatedDelete(String path, {Map<String, dynamic>? queryParameters}) async {
    final uri = createUri(path, queryParameters: queryParameters);
    _logger.debug('DELETE: $uri');
    
    try {
      // Always use getAuthHeaders to get the current token
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
  static bool _initialized = false;
  
  // Initialize core services
  static void initialize() {
    if (_initialized) return;
    
    _initialized = true;
    final logger = Logger('ServiceLocator');
    logger.info('ServiceLocator initialized');
  }
  
  static void register<T>(T service) {
    _services[T] = service!;
  }
  
  static T get<T>() {
    if (!_initialized) {
      initialize();
    }
    
    if (_services.containsKey(T)) {
      return _services[T] as T;
    }
    throw Exception('Service $T not registered');
  }
}
