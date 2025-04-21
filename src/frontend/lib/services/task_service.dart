import 'dart:convert';
import '../models/task.dart';
import '../utils/logger.dart';
import 'base_service.dart';

class TaskService extends BaseService {
  final Logger _logger = Logger('TaskService');

  Future<List<Task>> fetchTasks({String? completed, String? noteId}) async {
    try {
      // Build query parameters
      final queryParams = <String, dynamic>{};
      if (completed != null) queryParams['completed'] = completed;
      if (noteId != null) queryParams['note_id'] = noteId;
      
      _logger.info('Fetching tasks with params: $queryParams');
      final response = await authenticatedGet(
        '/api/v1/tasks',
        queryParams: queryParams
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
    final response = await authenticatedDelete('/api/v1/tasks/$id');

    if (response.statusCode != 204) {
      throw Exception('Failed to delete task: ${response.statusCode}');
    }
  }

  Future<Task> updateTask(String id, {String? title, bool? isCompleted}) async {
    final Map<String, dynamic> updates = {};
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
      final response = await authenticatedGet('/api/v1/tasks/$id');
      
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
