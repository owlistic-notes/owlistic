import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/note.dart';
import '../models/notebook.dart';
import '../utils/logger.dart';
import 'base_service.dart';
import '../providers/auth_provider.dart';

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
  
  Future<void> restoreItem(String type, String id, {String? userId}) async {
    try {
      // Build query parameters - server requires user_id
      Map<String, dynamic> params = {};
      if (userId != null) {
        params['user_id'] = userId;
      }
      
      // Use authenticatedPost from BaseService with auth headers
      final response = await authenticatedPost(
        '/api/v1/trash/restore/$type/$id',
        {},
        queryParameters: params
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to restore item: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in restoreItem', e);
      rethrow;
    }
  }
  
  Future<void> permanentlyDeleteItem(String type, String id, {String? userId}) async {
    try {
      // Build query parameters - server requires user_id
      Map<String, dynamic> params = {};
      if (userId != null) {
        params['user_id'] = userId;
      }
      
      // Use authenticatedDelete from BaseService with auth headers
      final response = await authenticatedDelete(
        '/api/v1/trash/$type/$id',
        queryParameters: params
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
  
  Future<void> emptyTrash({String? userId}) async {
    try {
      // Build query parameters - server requires user_id
      Map<String, dynamic> params = {};
      if (userId != null) {
        params['user_id'] = userId;
      }
      
      // Use authenticatedDelete from BaseService with auth headers
      final response = await authenticatedDelete(
        '/api/v1/trash',
        queryParameters: params
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
