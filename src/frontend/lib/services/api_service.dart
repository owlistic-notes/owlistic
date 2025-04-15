import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/note.dart';
import '../models/task.dart';
import '../models/notebook.dart';

class ApiService {
  static final String baseUrl = dotenv.env['BASE_URL'] ?? 'http://localhost:8080';

  static Future<List<Note>> fetchNotes() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/notes'),
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

  static Future<List<Task>> fetchTasks() async {
    try {
      print('Fetching tasks from: $baseUrl/api/v1/tasks');
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/tasks'),
        headers: {
          'Accept': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );
      print('Response status: ${response.statusCode}');
      print('Response headers: ${response.headers}');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        print('Parsed JSON data length: ${data.length}');
        print('First task data: ${data.isNotEmpty ? data.first : "no tasks"}');
        final tasks = data.map((json) => Task.fromJson(json)).toList();
        print('Converted to ${tasks.length} Task objects');
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

  static Future<Task> createTask(String title, String noteId) async {
    try {
      final taskResponse = await http.post(
        Uri.parse('$baseUrl/api/v1/tasks'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'title': title,
          'is_completed': false,
          'user_id': '90a12345-f12a-98c4-a456-513432930000',
          'note_id': noteId
        }),
      );

      if (taskResponse.statusCode == 201) {
        return Task.fromJson(json.decode(taskResponse.body));
      } else {
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

  static Future<List<Notebook>> fetchNotebooks() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/notebooks'),
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
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/notes/notebook/$notebookId'),
        headers: {
          'Accept': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Note.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load notebook notes: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in fetchNotebookNotes: $e');
      rethrow;
    }
  }
}
