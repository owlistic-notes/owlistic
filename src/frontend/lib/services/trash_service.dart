import 'dart:convert';
import '../models/note.dart';
import '../models/notebook.dart';
import '../utils/logger.dart';
import 'base_service.dart';

class TrashService extends BaseService {
  final Logger _logger = Logger('TrashService');

  Future<Map<String, dynamic>> fetchTrashedItems({
    Map<String, dynamic>? queryParams
  }) async {
    try {
      // Build base query parameters
      Map<String, dynamic> params = {};
      
      // Add any additional query parameters
      if (queryParams != null) {
        params.addAll(queryParams);
      }
      
      // Use authenticatedGet from BaseService with auth headers
      final response = await authenticatedGet(
        '/api/v1/trash',
        queryParameters: params
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        final List<dynamic> notesList = data['notes'] ?? [];
        final List<dynamic> notebooksList = data['notebooks'] ?? [];
        
        final parsedNotes = notesList.map((n) => Note.fromJson(n)).toList();
        final parsedNotebooks = notebooksList.map((nb) => Notebook.fromJson(nb)).toList();
        
        return {
          'notes': parsedNotes,
          'notebooks': parsedNotebooks,
        };
      } else {
        throw Exception('Failed to load trashed items: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in fetchTrashedItems', e);
      rethrow;
    }
  }
  
  Future<void> restoreItem(String type, String id) async {
    try {
      // Use authenticatedPost from BaseService with auth headers
      final response = await authenticatedPost(
        '/api/v1/trash/restore/$type/$id',
        {},
        queryParameters: {}
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to restore item: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in restoreItem', e);
      rethrow;
    }
  }
  
  Future<void> permanentlyDeleteItem(String type, String id) async {
    try {
      // Use authenticatedDelete from BaseService with auth headers
      final response = await authenticatedDelete(
        '/api/v1/trash/$type/$id',
        queryParameters: {}
      );
      
      // Server returns 200 for success, not 204
      if (response.statusCode != 200) {
        throw Exception('Failed to permanently delete item: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in permanentlyDeleteItem', e);
      rethrow;
    }
  }
  
  Future<void> emptyTrash() async {
    try {
      // Use authenticatedDelete from BaseService with auth headers
      final response = await authenticatedDelete(
        '/api/v1/trash',
        queryParameters: {}
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to empty trash: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in emptyTrash', e);
      rethrow;
    }
  }
}
