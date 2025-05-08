import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../utils/logger.dart';

// Base service class with minimal responsibilities
abstract class BaseService {
  static final Logger _logger = Logger('BaseService');
  
  // Base URL from SharedPreferences
  static String? _cachedBaseUrl;
  
  // Static token accessor that can be set by AuthService
  static String? _authToken;
  
  // Setter for the auth token that AuthService can call
  static void setAuthToken(String? token) {
    _authToken = token;
  }
  
  // Getter for the auth token
  static String? get authToken => _authToken;
  
  // Get base URL from SharedPreferences
  static Future<String?> _getBaseUrl() async {
    // Return cached URL if available
    if (_cachedBaseUrl != null) {
      return _cachedBaseUrl!;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('api_url');
      
      if (url != null && url.isNotEmpty) {
        _cachedBaseUrl = url;
        return url;
      }
    } catch (e) {
      _logger.error('Error getting base URL from SharedPreferences', e);
    }
    return null;
  }
  
  // Reset cached URL when it changes
  static void resetCachedUrl() {
    _cachedBaseUrl = null;
  }
  
  // Create URI helper
  Future<Uri> createUri(String path, {Map<String, dynamic>? queryParameters}) async {
    // Validate path
    if (!path.startsWith('/')) {
      path = '/$path';
    }
    
    // Get base URL from SharedPreferences
    final baseUrl = await _getBaseUrl();
    
    // Build full URL
    String fullUrl = baseUrl! + path;
    
    // Convert all query parameter values to strings
    Map<String, String>? stringParams;
    if (queryParameters != null) {
      stringParams = {};
      queryParameters.forEach((key, value) {
        stringParams![key] = value.toString();
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
    final uri = await createUri(path, queryParameters: queryParameters);
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
    final uri = await createUri(path, queryParameters: queryParameters);
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
    final uri = await createUri(path, queryParameters: queryParameters);
    _logger.debug('PUT: $uri');
    
    try {
      final bodyJson = jsonEncode(body);
      // Always use getAuthHeaders to get the current token
      final response = await http.put(
        uri,
        headers: getAuthHeaders(),
        body: bodyJson,
      );
      _validateResponse(response, 'PUT', uri.toString(), body: body);
      return response;
    } catch (e) {
      _logger.error('HTTP PUT error: $path', e);
      rethrow;
    }
  }

  Future<http.Response> authenticatedDelete(String path, {Map<String, dynamic>? queryParameters}) async {
    final uri = await createUri(path, queryParameters: queryParameters);
    _logger.debug('DELETE: $uri');
    
    try {
      // Always use getAuthHeaders to get the current token
      final response = await http.delete(
        uri,
        headers: getAuthHeaders(),
      );
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
        'HTTP $method request failed: $url\n'
        'Status: ${response.statusCode}\n'
        'Response: ${response.body}'
      );
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
