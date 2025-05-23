import 'dart:convert';
import 'package:owlistic/models/note.dart';
import 'base_service.dart';
import 'package:owlistic/utils/logger.dart';

class NoteService extends BaseService {
  final Logger _logger = Logger('NoteService');
  
  // Fetch all notes with pagination
  Future<List<Note>> fetchNotes({
    int page = 1, 
    int pageSize = 20,
    String? notebookId,
    Map<String, dynamic>? queryParams,
  }) async {
    try {
      // Build query parameters for pagination
      final Map<String, dynamic> params = {
        'page': page.toString(),
        'page_size': pageSize.toString(),
      };
      
      // Add notebookId filter if provided
      if (notebookId != null && notebookId.isNotEmpty) {
        params['notebook_id'] = notebookId;
      }
      
      // Add any additional query parameters
      if (queryParams != null) {
        params.addAll(queryParams);
      }
      
      _logger.debug('Fetching notes with params: $params');
      
      // Use the authenticated GET helper method
      final response = await authenticatedGet(
        '/api/v1/notes',
        queryParameters: params,
      );
      
      if (response.statusCode == 200) {
        final dynamic responseData = jsonDecode(response.body);
        List<dynamic> notesJson;
        
        // Handle different response formats
        if (responseData is List) {
          // Direct list of notes
          notesJson = responseData;
        } else if (responseData is Map) {
          // Response with data field containing list of notes
          notesJson = responseData['data'] ?? [];
        } else {
          _logger.error('Unexpected response format: ${response.body}');
          throw Exception('Unexpected response format');
        }
        
        return notesJson.map((json) => Note.fromJson(json)).toList();
      } else {
        _logger.error('Failed to fetch notes: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to fetch notes');
      }
    } catch (e) {
      _logger.error('Error fetching notes', e);
      rethrow;
    }
  }

  // Add this method to fetch notes for a specific notebook
  Future<List<Note>> fetchNotesForNotebook(String notebookId) async {
    _logger.debug('Fetching notes for notebook: $notebookId');
    try {
      final Map<String, dynamic> params = {
        'notebook_id': notebookId,
      };
      
      final response = await authenticatedGet(
        '/api/v1/notes',
        queryParameters: params,
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _logger.debug('Fetched ${data.length} notes for notebook $notebookId');
        return data.map((json) => Note.fromJson(json)).toList();
      } else {
        _logger.error('Failed to fetch notes for notebook: ${response.statusCode}');
        throw Exception('Failed to fetch notes for notebook');
      }
    } catch (e) {
      _logger.error('Error fetching notes for notebook $notebookId', e);
      rethrow;
    }
  }

  Future<Note> createNote(String notebookId, String title) async {
    try {
      final response = await authenticatedPost(
        '/api/v1/notes',
        {
          'title': title,
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
    
    try {
      final response = await authenticatedDelete(
        '/api/v1/notes/$id'
      );

      // Server returns 204 No Content on successful deletion
      if (response.statusCode != 204) {
        _logger.error('Delete note failed: ${response.statusCode}\nBody: ${response.body}');
        throw Exception('Failed to delete note: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error deleting note', e);
      rethrow;
    }
  }

  Future<Note> updateNote(
    String id, 
    String? title, 
    {String? notebookId, Map<String, dynamic>? queryParams}
  ) async {
    try {
      _logger.info('Updating note $id with title: $title, notebookId: $notebookId');
      
      // Build payload with only the fields that should be updated
      final Map<String, dynamic> payload = {};
      if (title != null) {
        payload['title'] = title;
      }
      if (notebookId != null) {
        payload['notebook_id'] = notebookId;
      }
      
      // Perform the PUT request with query parameters if provided
      final response = await authenticatedPut(
        '/api/v1/notes/$id',
        payload,
        queryParameters: queryParams
      );

      if (response.statusCode == 200) {
        _logger.info('Note updated successfully');
        return Note.fromJson(json.decode(response.body));
      } else {
        _logger.error('Update note failed: ${response.statusCode}\nBody: ${response.body}');
        throw Exception('Failed to update note: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in updateNote', e);
      rethrow;
    }
  }

  Future<Note> getNote(String id) async {
    try {
      _logger.debug('Getting note: $id');
      
      final response = await authenticatedGet(
        '/api/v1/notes/$id'
      );
      
      if (response.statusCode == 200) {
        return Note.fromJson(json.decode(response.body));
      } else {
        _logger.error('Failed to load note: Status ${response.statusCode}');
        throw Exception('Failed to load note: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in getNote', e);
      rethrow;
    }
  }

  Future<List<Note>> getNotes() async {
    try {
      final response = await authenticatedGet('/api/v1/notes');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final notes = data.map((json) => Note.fromJson(json)).toList();
        return notes;
      } else {
        throw Exception('Failed to load notes: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in getNotes', e);
      rethrow;
    }
  }
}
