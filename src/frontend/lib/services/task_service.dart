import 'dart:convert';
import '../models/task.dart';
import '../utils/logger.dart';
import 'base_service.dart';
import 'auth_service.dart';

class TaskService extends BaseService {
  final Logger _logger = Logger('TaskService');

  // Helper method to get current user ID
  Future<String?> _getCurrentUserId() async {
    final authService = AuthService();
    return authService.getCurrentUserId();
  }

  Future<List<Task>> fetchTasks({
    String? completed, 
    String? noteId, 
    String? userId,
    Map<String, dynamic>? queryParams,
  }) async {
    try {
      // Get current user ID if not provided
      userId ??= await _getCurrentUserId();
      if (userId == null) {
        throw Exception('User ID is required for security reasons');
      }
      
      // Build query parameters
      final Map<String, dynamic> params = {
        'user_id': userId, // Always include user ID
      };
      
      if (completed != null) params['completed'] = completed;
      if (noteId != null) params['note_id'] = noteId;
      
      // Add any additional query parameters
      if (queryParams != null) {
        params.addAll(queryParams);
      }
      
      _logger.info('Fetching tasks with params: $params');
      final response = await authenticatedGet(
        '/api/v1/tasks',
        queryParameters: params
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

  Future<Task> createTask(String title, String noteId, String userId, {String? blockId}) async {
    try {
      final taskData = {
        'title': title,
        'is_completed': false,
        'user_id': userId,
        'note_id': noteId,
      };
      
      if (blockId != null && blockId.isNotEmpty && blockId != '00000000-0000-0000-0000-000000000000') {
        taskData['block_id'] = blockId;
      }

      final taskResponse = await authenticatedPost(
        '/api/v1/tasks',
        taskData
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

  Future<void> deleteTask(String id) async {
    // Get current user ID
    String? userId = await _getCurrentUserId();
    if (userId == null) {
      throw Exception('User ID is required for security reasons');
    }
    
    final response = await authenticatedDelete(
      '/api/v1/tasks/$id',
      queryParameters: {'user_id': userId}
    );

    if (response.statusCode != 204) {
      throw Exception('Failed to delete task: ${response.statusCode}');
    }
  }

  Future<Task> updateTask(String id, {String? title, bool? isCompleted}) async {
    // Get current user ID
    String? userId = await _getCurrentUserId();
    if (userId == null) {
      throw Exception('User ID is required for security reasons');
    }
    
    final Map<String, dynamic> updates = {
      'user_id': userId, // Include user ID in request body
    };
    
    if (title != null) updates['title'] = title;
    if (isCompleted != null) updates['is_completed'] = isCompleted;

    final response = await authenticatedPut(
      '/api/v1/tasks/$id',
      updates
    );

    if (response.statusCode == 200) {
      return Task.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to update task: ${response.statusCode}');
    }
  }

  Future<Task> getTask(String id) async {
    try {
      // Get current user ID
      String? userId = await _getCurrentUserId();
      if (userId == null) {
        throw Exception('User ID is required for security reasons');
      }
      
      final response = await authenticatedGet(
        '/api/v1/tasks/$id',
        queryParameters: {'user_id': userId}
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
}
