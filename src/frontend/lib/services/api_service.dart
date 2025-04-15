import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/note.dart';
import '../models/task.dart';

class ApiService {
  static final String baseUrl = dotenv.env['BASE_URL'] ?? 'http://localhost:8080';

  static Future<List<Note>> fetchNotes() async {
    try {
      print('Fetching notes from: $baseUrl/api/v1/notes');
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/notes'),
        headers: {
          'Accept': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );
      print('Response status: ${response.statusCode}');
      print('Response headers: ${response.headers}');
      print('Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        print('Parsed JSON data: $data');
        final notes = data.map((json) => Note.fromJson(json)).toList();
        print('Converted to ${notes.length} Note objects');
        return notes;
      } else {
        throw Exception('Failed to load notes: ${response.statusCode}\nBody: ${response.body}');
      }
    } catch (e, stack) {
      print('Error in fetchNotes: $e');
      print('Stack trace: $stack');
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

  static Future<Note> createNote(String title, String content) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/notes'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'title': title,  // Changed from 'Title' to 'title'
          'content': content,  // Changed from 'Content' to 'content'
          'user_id': '90a12345-f12a-98c4-a456-513432930000',  // Changed from 'UserID' to 'user_id'
        }),
      );

      print('Create note response: ${response.statusCode}');
      print('Response body: ${response.body}');

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

  static Future<Note> updateNote(String id, String title, String content) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/v1/notes/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'Title': title,
        'Content': content,
      }),
    );

    if (response.statusCode == 200) {
      return Note.fromJson(json.decode(response.body));
    } else {
      print('Update note failed: ${response.statusCode}\nBody: ${response.body}');
      throw Exception('Failed to update note: ${response.statusCode}');
    }
  }

  static Future<Task> createTask(String title) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/tasks'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'title': title,
        'is_completed': false,
        'user_id': '90a12345-f12a-98c4-a456-513432930000', // TODO: Get from auth
      }),
    );

    if (response.statusCode == 201) {
      return Task.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to create task: ${response.statusCode}');
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
    if (title != null) updates['Title'] = title;
    if (isCompleted != null) updates['IsCompleted'] = isCompleted;

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
}
