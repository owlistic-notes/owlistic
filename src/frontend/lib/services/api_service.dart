import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:thinkstack/models/user.dart';
import '../models/note.dart';
import '../models/task.dart';
import '../models/notebook.dart';
import '../models/block.dart';
import '../utils/logger.dart';

class ApiService {
  static final Logger _logger = Logger('ApiService');
  static final String baseUrl = dotenv.env['BASE_URL'] ?? 'http://localhost:8080';
  static String? _token;
  static User? _currentUser;

  // Helper method to get authenticated headers
  static Map<String, String> _getAuthHeaders() {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Access-Control-Allow-Origin': '*',
    };
    
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    
    return headers;
  }
  
  // Helper method to get current user ID or throw exception
  static String _getCurrentUserId() {
    if (_currentUser == null || _currentUser!.id.isEmpty) {
      throw Exception('No authenticated user');
    }
    return _currentUser!.id;
  }

  static Future<List<Note>> fetchNotes({
    String? notebookId, 
    String? title,
    int page = 1,
    int pageSize = 20
  }) async {
    try {
      // Build query parameters
      final queryParams = <String, String>{};
      if (notebookId != null) queryParams['notebook_id'] = notebookId;
      if (title != null) queryParams['title'] = title;
      
      // Add pagination parameters
      queryParams['page'] = page.toString();
      queryParams['page_size'] = pageSize.toString();
      
      final uri = Uri.parse('$baseUrl/api/v1/notes').replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: _getAuthHeaders(),
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Note.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load notes: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in fetchNotes', e);
      rethrow;
    }
  }

  static Future<List<Task>> fetchTasks({String? completed, String? noteId}) async {
    try {
      // Build query parameters
      final queryParams = <String, String>{};
      if (completed != null) queryParams['completed'] = completed;
      if (noteId != null) queryParams['note_id'] = noteId;
      
      final uri = Uri.parse('$baseUrl/api/v1/tasks').replace(queryParameters: queryParams);
      
      _logger.info('Fetching tasks from: $uri');
      final response = await http.get(
        uri,
        headers: _getAuthHeaders(),
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final tasks = data.map((json) => Task.fromJson(json)).toList();
        return tasks;
      } else {
        throw Exception('Failed to load tasks: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in fetchTasks', e);
      rethrow;
    }
  }

  static Future<Note> createNote(String notebookId, String title) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/notes'),
        headers: _getAuthHeaders(),
        body: json.encode({
          'title': title,
          'user_id': _getCurrentUserId(),
          'notebook_id': notebookId,
          'blocks': [
            {
              'content': '',
              'type': 'text',
              'order': 0
            }
          ]
        }),
      );

      if (response.statusCode == 201) {
        return Note.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to create note: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in createNote', e);
      rethrow;
    }
  }

  static Future<void> deleteNote(String id) async {
    _logger.info('Deleting note with ID: $id');
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v1/notes/$id'),
      headers: _getAuthHeaders(),
    );

    if (response.statusCode != 204) {
      _logger.error('Delete note failed: ${response.statusCode}\nBody: ${response.body}');
      throw Exception('Failed to delete note: ${response.statusCode}');
    }
  }

  static Future<Note> updateNote(String id, String title) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/v1/notes/$id'),
      headers: _getAuthHeaders(),
      body: json.encode({
        'title': title,
      }),
    );

    if (response.statusCode == 200) {
      return Note.fromJson(json.decode(response.body));
    } else {
      _logger.error('Update note failed: ${response.statusCode}\nBody: ${response.body}');
      throw Exception('Failed to update note: ${response.statusCode}');
    }
  }

  static Future<Task> createTask(String title, String noteId, {String? blockId}) async {
    try {
      final taskData = {
        'title': title,
        'is_completed': false,
        'user_id': _getCurrentUserId(),
        'note_id': noteId,
      };
      
      if (blockId != null && blockId.isNotEmpty && blockId != '00000000-0000-0000-0000-000000000000') {
        taskData['block_id'] = blockId;
      }

      final taskResponse = await http.post(
        Uri.parse('$baseUrl/api/v1/tasks'),
        headers: _getAuthHeaders(),
        body: json.encode(taskData),
      );

      if (taskResponse.statusCode == 201) {
        return Task.fromJson(json.decode(taskResponse.body));
      } else {
        throw Exception('Failed to create task: ${taskResponse.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in createTask', e);
      rethrow;
    }
  }

  static Future<void> deleteTask(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v1/tasks/$id'),
      headers: _getAuthHeaders(),
    );

    if (response.statusCode != 204) {
      throw Exception('Failed to delete task: ${response.statusCode}');
    }
  }

  static Future<Task> updateTask(String id, {String? title, bool? isCompleted}) async {
    final Map<String, dynamic> updates = {};
    if (title != null) updates['title'] = title;
    if (isCompleted != null) updates['is_completed'] = isCompleted;

    final response = await http.put(
      Uri.parse('$baseUrl/api/v1/tasks/$id'),
      headers: _getAuthHeaders(),
      body: json.encode(updates),
    );

    if (response.statusCode == 200) {
      return Task.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to update task: ${response.statusCode}');
    }
  }

  static Future<List<Notebook>> fetchNotebooks({
    String? name,
    int page = 1,
    int pageSize = 20
  }) async {
    try {
      // Build query parameters
      final queryParams = <String, String>{};
      if (name != null) queryParams['name'] = name;
      
      // Add pagination parameters
      queryParams['page'] = page.toString();
      queryParams['page_size'] = pageSize.toString();
      
      final uri = Uri.parse('$baseUrl/api/v1/notebooks').replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: _getAuthHeaders(),
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Notebook.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load notebooks');
      }
    } catch (e) {
      _logger.error('Error in fetchNotebooks', e);
      rethrow;
    }
  }

  static Future<Notebook> createNotebook(String name, String description) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/notebooks'),
        headers: _getAuthHeaders(),
        body: json.encode({
          'name': name,
          'description': description,
          'user_id': _getCurrentUserId(),
        }),
      );

      if (response.statusCode == 201) {
        return Notebook.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to create notebook');
      }
    } catch (e) {
      _logger.error('Error in createNotebook', e);
      rethrow;
    }
  }

  static Future<void> deleteNoteFromNotebook(String notebookId, String noteId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v1/notes/$noteId'),
      headers: _getAuthHeaders(),
    );

    if (response.statusCode != 204) {
      throw Exception('Failed to delete note');
    }
  }

  static Future<Notebook> updateNotebook(String id, String name, String description) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/v1/notebooks/$id'),
        headers: _getAuthHeaders(),
        body: json.encode({
          'name': name,
          'description': description,
        }),
      );

      if (response.statusCode == 200) {
        return Notebook.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to update notebook');
      }
    } catch (e) {
      _logger.error('Error in updateNotebook', e);
      rethrow;
    }
  }

  static Future<void> deleteNotebook(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/v1/notebooks/$id'),
        headers: _getAuthHeaders(),
      );

      if (response.statusCode != 204) {
        throw Exception('Failed to delete notebook');
      }
    } catch (e) {
      _logger.error('Error in deleteNotebook', e);
      rethrow;
    }
  }

  static Future<List<Note>> fetchNotebookNotes(String notebookId) async {
    return fetchNotes(notebookId: notebookId);
  }

  static Future<List<Block>> fetchBlocksForNote(String noteId) async {
    try {
      // Use query parameter instead of path parameter
      final queryParams = <String, String>{'note_id': noteId};
      final uri = Uri.parse('$baseUrl/api/v1/blocks').replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: _getAuthHeaders(),
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Block.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load blocks');
      }
    } catch (e) {
      _logger.error('Error in fetchBlocksForNote', e);
      rethrow;
    }
  }

  static Future<Block> createBlock(String noteId, dynamic content, String type, int order) async {
    // Convert content to proper format for API
    Map<String, dynamic> contentMap;
    
    if (content is String) {
      try {
        contentMap = json.decode(content);
      } catch (e) {
        contentMap = {'text': content};
      }
    } else if (content is Map) {
      contentMap = Map<String, dynamic>.from(content);
    } else {
      throw ArgumentError('Content must be a String or Map');
    }
    
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/blocks'),
      headers: _getAuthHeaders(),
      body: jsonEncode({
        'note_id': noteId,
        'content': contentMap,
        'type': type,
        'order': order,
        'user_id': _getCurrentUserId(),
      }),
    );
    
    if (response.statusCode == 201) {
      return Block.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create block: ${response.statusCode}');
    }
  }

  static Future<void> deleteBlock(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/v1/blocks/$id'),
        headers: _getAuthHeaders(),
      );

      if (response.statusCode != 204) {
        throw Exception('Failed to delete block');
      }
    } catch (e) {
      _logger.error('Error in deleteBlock', e);
      rethrow;
    }
  }

  static Future<Block> updateBlock(String blockId, dynamic content, {String? type}) async {
    // Convert content to proper format for API
    Map<String, dynamic> contentMap;
    
    if (content is String) {
      try {
        contentMap = json.decode(content);
      } catch (e) {
        contentMap = {'text': content};
      }
    } else if (content is Map) {
      contentMap = Map<String, dynamic>.from(content);
    } else {
      throw ArgumentError('Content must be a String or Map');
    }
    
    final Map<String, dynamic> body = {
      'content': contentMap,
      'user_id': _getCurrentUserId(),
    };
    
    if (type != null) {
      body['type'] = type;
    }
    
    final response = await http.put(
      Uri.parse('$baseUrl/api/v1/blocks/$blockId'),
      headers: _getAuthHeaders(),
      body: jsonEncode(body),
    );
    
    if (response.statusCode == 200) {
      return Block.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to update block: ${response.statusCode}');
    }
  }

  static Future<Block> getBlock(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/blocks/$id'),
        headers: _getAuthHeaders(),
      );
      
      if (response.statusCode == 200) {
        return Block.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load block');
      }
    } catch (e) {
      _logger.error('Error in getBlock', e);
      rethrow;
    }
  }

  static Future<Note> getNote(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/notes/$id'),
        headers: _getAuthHeaders(),
      );
      
      if (response.statusCode == 200) {
        return Note.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load note');
      }
    } catch (e) {
      _logger.error('Error in getNote', e);
      rethrow;
    }
  }

  static Future<Notebook> getNotebook(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/notebooks/$id'),
        headers: _getAuthHeaders(),
      );
      
      if (response.statusCode == 200) {
        return Notebook.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load notebook');
      }
    } catch (e) {
      _logger.error('Error in getNotebook', e);
      rethrow;
    }
  }

  static Future<Task> getTask(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/tasks/$id'),
        headers: _getAuthHeaders(),
      );
      
      if (response.statusCode == 200) {
        return Task.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load task');
      }
    } catch (e) {
      _logger.error('Error in getTask', e);
      rethrow;
    }
  }

  // Trash related methods
  static Future<Map<String, dynamic>> fetchTrashedItems() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/trash'),
        headers: _getAuthHeaders(),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        final List<dynamic> notesList = data['notes'] ?? [];
        final List<dynamic> notebooksList = data['notebooks'] ?? [];
        
        final parsedNotes = notesList.map((n) => Note.fromJson(n)).toList();
        final parsedNotebooks = notebooksList.map((nb) => Notebook.fromJson(nb)).toList();
        
        return {
          'notes': parsedNotes,
          'notebooks': parsedNotebooks,
        };
      } else {
        throw Exception('Failed to load trashed items: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in fetchTrashedItems', e);
      rethrow;
    }
  }
  
  static Future<void> restoreItem(String type, String id) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/trash/restore/$type/$id'),
        headers: _getAuthHeaders(),
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to restore item: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in restoreItem', e);
      rethrow;
    }
  }
  
  static Future<void> permanentlyDeleteItem(String type, String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/v1/trash/$type/$id'),
        headers: _getAuthHeaders(),
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to permanently delete item: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in permanentlyDeleteItem', e);
      rethrow;
    }
  }
  
  static Future<void> emptyTrash() async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/v1/trash'),
        headers: _getAuthHeaders(),
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to empty trash: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in emptyTrash', e);
      rethrow;
    }
  }

  // Authentication methods
  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['token']; // Update token for future requests
        
        // Parse the user information from the token
        await _parseUserFromToken(_token!);
        
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

  static Future<void> _parseUserFromToken(String token) async {
    try {
      final tokenParts = token.split('.');
      if (tokenParts.length != 3) {
        _logger.error("Invalid JWT token format");
        return;
      }
      
      String normalized = base64Url.normalize(tokenParts[1]);
      final payloadJson = utf8.decode(base64Url.decode(normalized));
      final payload = jsonDecode(payloadJson);
      
      _currentUser = User(
        id: payload['UserID'] ?? payload['user_id'] ?? payload['sub'] ?? '',
        email: payload['email'] ?? '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      _logger.info("User ID from token: ${_currentUser!.id}");
    } catch (e) {
      _logger.error('Error parsing token', e);
    }
  }

  static Future<User> register(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/register'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return User.fromJson(data);
      } else {
        _logger.error('Registration failed with status: ${response.statusCode}');
        throw Exception('Failed to register: ${response.body}');
      }
    } catch (e) {
      _logger.error('Error during registration', e);
      throw e;
    }
  }

  static Future<User?> getUserProfile() async {
    if (_token == null) return null;
    
    try {
      _logger.info("Parsing JWT token to extract user info");
      
      // Extract user information from token
      final tokenParts = _token!.split('.');
      if (tokenParts.length != 3) {
        _logger.error("Invalid JWT token format");
        return null; // Not a valid JWT
      }
      
      // Decode the payload part (second part)
      String normalized = base64Url.normalize(tokenParts[1]);
      final payloadJson = utf8.decode(base64Url.decode(normalized));
      final payload = jsonDecode(payloadJson);
      
      _logger.info("Successfully extracted user info from token: ${payload['email']}");
      
      // Create a user object from the token payload
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

  static Future<User> updateUserProfile(Map<String, dynamic> data) async {
    try {
      // Since we don't have a proper endpoint, we'll simulate an update
      // In a real app, you would use a proper API endpoint
      _logger.info('Profile update would send data: $data');
      
      // Return a mock updated user
      return User(
        id: data['id'] ?? '',
        email: data['email'] ?? '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      _logger.error('Error updating user profile', e);
      throw e;
    }
  }

  static Future<bool> changePassword(String currentPassword, String newPassword) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/v1/auth/password'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $_token',
        },
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

  static User? getCurrentUser() {
    return _currentUser;
  }

  static void setToken(String token) {
    _token = token;
    _parseUserFromToken(token);
  }

  static void clearToken() {
    _token = null;
    _currentUser = null;
  }
}
