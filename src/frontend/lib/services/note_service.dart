import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/note.dart';
import 'base_service.dart';
import '../utils/logger.dart';

class NoteService extends BaseService {
  final Logger _logger = Logger('NoteService');
  
  // Fetch all notes with pagination
  Future<List<Note>> fetchNotes({int page = 1, int pageSize = 20}) async {
    try {
      // Use the authenticated GET helper method
      final response = await authenticatedGet(
        '/api/v1/notes',
        queryParams: {
          'page': page.toString(),
          'page_size': pageSize.toString(),
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> notesJson = data['data'] ?? [];
        return notesJson.map((json) => Note.fromJson(json)).toList();
      } else {
        _logger.error('Failed to fetch notes: ${response.statusCode}');
        throw Exception('Failed to fetch notes');
      }
    } catch (e) {
      _logger.error('Error fetching notes', e);
      throw e;
    }
  }

  Future<Note> createNote(String notebookId, String title, String userId) async {
    try {
      final response = await authenticatedPost(
        '/api/v1/notes',
        {
          'title': title,
          'user_id': userId,
          'notebook_id': notebookId,
          'blocks': [
            {
              'content': '',
              'type': 'text',
              'order': 0
            }
          ]
        }
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

  Future<void> deleteNote(String id) async {
    _logger.info('Deleting note with ID: $id');
    final response = await authenticatedDelete('/api/v1/notes/$id');

    if (response.statusCode != 204) {
      _logger.error('Delete note failed: ${response.statusCode}\nBody: ${response.body}');
      throw Exception('Failed to delete note: ${response.statusCode}');
    }
  }

  Future<Note> updateNote(String id, String title) async {
    final response = await authenticatedPut(
      '/api/v1/notes/$id',
      {'title': title}
    );

    if (response.statusCode == 200) {
      return Note.fromJson(json.decode(response.body));
    } else {
      _logger.error('Update note failed: ${response.statusCode}\nBody: ${response.body}');
      throw Exception('Failed to update note: ${response.statusCode}');
    }
  }

  Future<Note> getNote(String id) async {
    try {
      final response = await authenticatedGet('/api/v1/notes/$id');
      
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
}
