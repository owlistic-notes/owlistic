import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/note.dart';
import '../models/task.dart';
import '../models/notebook.dart';
import '../models/block.dart';

class ApiService {
  static final String baseUrl = dotenv.env['BASE_URL'] ?? 'http://localhost:8080';

  static Future<List<Note>> fetchNotes({
    String? userId, 
    String? notebookId, 
    String? title,
    int page = 1,
    int pageSize = 20
  }) async {
    try {
      // Build query parameters
      final queryParams = <String, String>{};
      if (userId != null) queryParams['user_id'] = userId;
      if (notebookId != null) queryParams['notebook_id'] = notebookId;
      if (title != null) queryParams['title'] = title;
      
      // Add pagination parameters
      queryParams['page'] = page.toString();
      queryParams['page_size'] = pageSize.toString();
      
      final uri = Uri.parse('$baseUrl/api/v1/notes').replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Note.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load notes: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in fetchNotes: $e');
      rethrow;
    }
  }

  static Future<List<Task>> fetchTasks({String? userId, String? completed, String? noteId}) async {
    try {
      // Build query parameters
      final queryParams = <String, String>{};
      if (userId != null) queryParams['user_id'] = userId;
      if (completed != null) queryParams['completed'] = completed;
      if (noteId != null) queryParams['note_id'] = noteId;
      
      final uri = Uri.parse('$baseUrl/api/v1/tasks').replace(queryParameters: queryParams);
      
      print('Fetching tasks from: $uri');
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );
      print('Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        print('Parsed JSON data length: ${data.length}');
        final tasks = data.map((json) => Task.fromJson(json)).toList();
        return tasks;
      } else {
        throw Exception('Failed to load tasks: ${response.statusCode}\nBody: ${response.body}');
      }
    } catch (e, stack) {
      print('Error in fetchTasks: $e');
      print('Stack trace: $stack');
      rethrow;
    }
  }

  static Future<Note> createNote(String notebookId, String title) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/notes'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'title': title,
          'user_id': '90a12345-f12a-98c4-a456-513432930000',
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
        throw Exception('Failed to create note: ${response.statusCode}\nBody: ${response.body}');
      }
    } catch (e) {
      print('Error in createNote: $e');
      rethrow;
    }
  }

  static Future<void> deleteNote(String id) async {
    print('Deleting note with ID: $id');
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v1/notes/$id'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode != 204) {
      print('Delete note failed: ${response.statusCode}\nBody: ${response.body}');
      throw Exception('Failed to delete note: ${response.statusCode}');
    }
  }

  static Future<Note> updateNote(String id, String title) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/v1/notes/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'title': title,
      }),
    );

    if (response.statusCode == 200) {
      return Note.fromJson(json.decode(response.body));
    } else {
      print('Update note failed: ${response.statusCode}\nBody: ${response.body}');
      throw Exception('Failed to update note: ${response.statusCode}');
    }
  }

  static Future<Task> createTask(String title, String noteId, {String? blockId}) async {
    try {
      final taskData = {
        'title': title,
        'is_completed': false,
        'user_id': '90a12345-f12a-98c4-a456-513432930000',
        'note_id': noteId,
      };
      
      // Only add blockId if it's provided and valid
      if (blockId != null && blockId.isNotEmpty && blockId != '00000000-0000-0000-0000-000000000000') {
        taskData['block_id'] = blockId;
      }
      
      print('Creating task with data: $taskData');

      final taskResponse = await http.post(
        Uri.parse('$baseUrl/api/v1/tasks'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(taskData),
      );

      if (taskResponse.statusCode == 201) {
        return Task.fromJson(json.decode(taskResponse.body));
      } else {
        print('Failed to create task: ${taskResponse.statusCode}, ${taskResponse.body}');
        throw Exception('Failed to create task: ${taskResponse.statusCode}');
      }
    } catch (e) {
      print('Error in createTask: $e');
      rethrow;
    }
  }

  static Future<void> deleteTask(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v1/tasks/$id'),
      headers: {'Content-Type': 'application/json'},
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
      headers: {'Content-Type': 'application/json'},
      body: json.encode(updates),
    );

    if (response.statusCode == 200) {
      return Task.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to update task: ${response.statusCode}');
    }
  }

  static Future<List<Notebook>> fetchNotebooks({
    String? userId, 
    String? name,
    int page = 1,
    int pageSize = 20
  }) async {
    try {
      // Build query parameters
      final queryParams = <String, String>{};
      if (userId != null) queryParams['user_id'] = userId;
      if (name != null) queryParams['name'] = name;
      
      // Add pagination parameters
      queryParams['page'] = page.toString();
      queryParams['page_size'] = pageSize.toString();
      
      final uri = Uri.parse('$baseUrl/api/v1/notebooks').replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Notebook.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load notebooks');
      }
    } catch (e) {
      print('Error in fetchNotebooks: $e');
      rethrow;
    }
  }

  static Future<Notebook> createNotebook(String name, String description) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/notebooks'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'description': description,
          'user_id': '90a12345-f12a-98c4-a456-513432930000',
        }),
      );

      if (response.statusCode == 201) {
        return Notebook.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to create notebook');
      }
    } catch (e) {
      print('Error in createNotebook: $e');
      rethrow;
    }
  }

  static Future<void> deleteNoteFromNotebook(String notebookId, String noteId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v1/notes/$noteId'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode != 204) {
      throw Exception('Failed to delete note');
    }
  }

  static Future<Notebook> updateNotebook(String id, String name, String description) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/v1/notebooks/$id'),
        headers: {'Content-Type': 'application/json'},
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
      print('Error in updateNotebook: $e');
      rethrow;
    }
  }

  static Future<void> deleteNotebook(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/v1/notebooks/$id'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 204) {
        throw Exception('Failed to delete notebook');
      }
    } catch (e) {
      print('Error in deleteNotebook: $e');
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
        headers: {
          'Accept': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Block.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load blocks');
      }
    } catch (e) {
      print('Error in fetchBlocksForNote: $e');
      rethrow;
    }
  }

  static Future<Block> createBlock(String noteId, String content, String type, int order) async {
    try {
      // Convert the order to a string to ensure proper parsing on the Go backend
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/blocks'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'note_id': noteId,
          'content': content,
          'type': type,
          'order': order.toString() // Send order as a string to avoid float64/int conversion issues
        }),
      );

      if (response.statusCode == 201) {
        return Block.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to create block');
      }
    } catch (e) {
      print('Error in createBlock: $e');
      rethrow;
    }
  }

  static Future<void> deleteBlock(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/v1/blocks/$id'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 204) {
        throw Exception('Failed to delete block');
      }
    } catch (e) {
      print('Error in deleteBlock: $e');
      rethrow;
    }
  }

  static Future<Block> updateBlock(String id, String content, {String? type}) async {
    try {
      final Map<String, dynamic> updates = {
        'content': content,
      };
      
      if (type != null) {
        updates['type'] = type;
      }
      
      final response = await http.put(
        Uri.parse('$baseUrl/api/v1/blocks/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(updates),
      );

      if (response.statusCode == 200) {
        return Block.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to update block: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in updateBlock: $e');
      rethrow;
    }
  }

  static Future<Block> getBlock(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/blocks/$id'),
        headers: {
          'Accept': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );
      
      if (response.statusCode == 200) {
        return Block.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load block');
      }
    } catch (e) {
      print('Error in getBlock: $e');
      rethrow;
    }
  }

  static Future<Note> getNote(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/notes/$id'),
        headers: {
          'Accept': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );
      
      if (response.statusCode == 200) {
        return Note.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load note');
      }
    } catch (e) {
      print('Error in getNote: $e');
      rethrow;
    }
  }

  static Future<Notebook> getNotebook(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/notebooks/$id'),
        headers: {
          'Accept': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );
      
      if (response.statusCode == 200) {
        return Notebook.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load notebook');
      }
    } catch (e) {
      print('Error in getNotebook: $e');
      rethrow;
    }
  }

  static Future<Task> getTask(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/tasks/$id'),
        headers: {
          'Accept': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );
      
      if (response.statusCode == 200) {
        return Task.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load task');
      }
    } catch (e) {
      print('Error in getTask: $e');
      rethrow;
    }
  }
}
