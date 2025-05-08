import 'dart:convert';
import '../models/task.dart';
import '../utils/logger.dart';
import 'base_service.dart';

class TaskService extends BaseService {
  final Logger _logger = Logger('TaskService');

  Future<List<Task>> fetchTasks({
    String? completed, 
    String? noteId,
    Map<String, dynamic>? queryParams,
  }) async {
    try {
      final Map<String, dynamic> params = {};
      
      if (completed != null) params['completed'] = completed;
      if (noteId != null) params['note_id'] = noteId;
      
      if (queryParams != null) {
        params.addAll(queryParams);
      }
      
      final response = await authenticatedGet(
        '/api/v1/tasks',
        queryParameters: params
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Task.fromJson(json)).toList();
      } else {
        _logger.error('Failed to load tasks: ${response.statusCode}, ${response.body}');
        throw Exception('Failed to load tasks: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in fetchTasks', e);
      rethrow;
    }
  }

  Future<Task> createTask(String title, String noteId, {String? blockId}) async {
    try {
      final taskData = {
        'title': title,
        'is_completed': false,
        'note_id': noteId,
      };
      
      if (blockId != null && blockId.isNotEmpty) {
        taskData['block_id'] = blockId;
      }

      final response = await authenticatedPost('/api/v1/tasks', taskData);

      if (response.statusCode == 201) {
        return Task.fromJson(json.decode(response.body));
      } else {
        _logger.error('Failed to create task: ${response.statusCode}, ${response.body}');
        throw Exception('Failed to create task: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in createTask', e);
      rethrow;
    }
  }

  Future<void> deleteTask(String id) async {
    try {
      final response = await authenticatedDelete('/api/v1/tasks/$id');

      if (response.statusCode != 204) {
        _logger.error('Failed to delete task: ${response.statusCode}, ${response.body}');
        throw Exception('Failed to delete task: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in deleteTask', e);
      rethrow;
    }
  }

  Future<Task> updateTask(String id, {String? title, bool? isCompleted}) async {
    try {
      final Map<String, dynamic> updates = {};
      
      if (title != null) updates['title'] = title;
      if (isCompleted != null) updates['is_completed'] = isCompleted;

      final response = await authenticatedPut('/api/v1/tasks/$id', updates);

      if (response.statusCode == 200) {
        return Task.fromJson(json.decode(response.body));
      } else {
        _logger.error('Failed to update task: ${response.statusCode}, ${response.body}');
        throw Exception('Failed to update task: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in updateTask', e);
      rethrow;
    }
  }

  Future<Task> getTask(String id) async {
    try {
      final response = await authenticatedGet('/api/v1/tasks/$id');
      
      if (response.statusCode == 200) {
        return Task.fromJson(json.decode(response.body));
      } else {
        _logger.error('Failed to get task: ${response.statusCode}, ${response.body}');
        throw Exception('Failed to get task: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in getTask', e);
      rethrow;
    }
  }
}
