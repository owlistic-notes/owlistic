import 'dart:convert';
import 'package:owlistic/models/task.dart';
import 'package:owlistic/utils/logger.dart';
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
      
      if (completed != null) params['is_completed'] = completed;
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
      // Create metadata with sync source
      final metadata = <String, dynamic>{};
      
      // Add block_id to metadata if provided
      if (blockId != null && blockId.isNotEmpty) {
        metadata['block_id'] = blockId;
      }
      
      final taskData = <String, dynamic>{
        'title': title,
        'is_completed': false,
        'note_id': noteId,
        'metadata': metadata,
      };

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

  Future<Task> updateTask(String id, {String? title, bool? isCompleted, String? noteId}) async {
    try {
      // Get existing task to maintain metadata
      Task existingTask;
      try {
        existingTask = await getTask(id);
      } catch (e) {
        _logger.error('Failed to fetch existing task before update', e);
        existingTask = Task(
          id: id,
          title: '',
          isCompleted: false,
          userId: '',
          noteId: '',
          metadata: {},
        );
      }
      
      // Create metadata with task_id and keep existing metadata
      final metadata = <String, dynamic>{};
      
      // Copy existing metadata
      if (existingTask.metadata != null) {
        metadata.addAll(existingTask.metadata!);
      }

      final updates = <String, dynamic>{
        'metadata': metadata,
      };
      
      // Add basic task properties
      updates['title'] = (title != null) ? title : existingTask.title;
      updates['note_id'] = (noteId != null) ? noteId : existingTask.noteId;
      updates['is_completed'] = (isCompleted != null) ? isCompleted : existingTask.isCompleted;

      final response = await authenticatedPut('/api/v1/tasks/$id', updates);

      if (response.statusCode == 200) {
        return Task.fromJson(json.decode(response.body));
      } else {
        _logger.error('Failed to update task: ${response.statusCode}');
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
