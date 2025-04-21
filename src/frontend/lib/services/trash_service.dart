import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/note.dart';
import '../models/notebook.dart';
import '../utils/logger.dart';
import 'base_service.dart';

class TrashService extends BaseService {
  final Logger _logger = Logger('TrashService');

  Future<Map<String, dynamic>> fetchTrashedItems({
    String? userId,
    Map<String, dynamic>? queryParams
  }) async {
    try {
      // Build base query parameters if userId is provided
      Map<String, dynamic> params = {};
      
      if (userId != null) {
        params['user_id'] = userId;
      }
      
      // Add any additional query parameters
      if (queryParams != null) {
        params.addAll(queryParams);
      }
      
      final uri = createUri('/api/v1/trash', queryParameters: params);
      
      final response = await http.get(
        uri,
        headers: getAuthHeaders(),
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
      final response = await http.post(
        createUri('/api/v1/trash/restore/$type/$id'),
        headers: getAuthHeaders(),
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
      final response = await http.delete(
        createUri('/api/v1/trash/$type/$id'),
        headers: getAuthHeaders(),
      );
      
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
      final response = await http.delete(
        createUri('/api/v1/trash'),
        headers: getAuthHeaders(),
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
