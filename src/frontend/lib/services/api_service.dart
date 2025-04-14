import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/note.dart';
import '../models/task.dart';

class ApiService {
  static final String baseUrl = dotenv.env['BASE_URL'] ?? 'http://localhost:5000';

  static Future<List<Note>> fetchNotes() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/notes'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Note.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load notes');
    }
  }

  static Future<List<Task>> fetchTasks() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/tasks'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Task.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load tasks');
    }
  }
}
