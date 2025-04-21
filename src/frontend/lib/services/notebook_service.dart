import 'dart:convert';
import '../models/notebook.dart';
import '../utils/logger.dart';
import 'base_service.dart';

class NotebookService extends BaseService {
  final Logger _logger = Logger('NotebookService');

  Future<List<Notebook>> fetchNotebooks({
    String? name,
    int page = 1,
    int pageSize = 20
  }) async {
    try {
      // Build query parameters
      final queryParams = <String, dynamic>{};
      if (name != null) queryParams['name'] = name;
      
      // Add pagination parameters
      queryParams['page'] = page;
      queryParams['page_size'] = pageSize;
      
      final response = await authenticatedGet(
        '/api/v1/notebooks',
        queryParams: queryParams
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Notebook.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load notebooks');
      }
    } catch (e) {
      _logger.error('Error in fetchNotebooks', e);
      rethrow;
    }
  }

  Future<Notebook> createNotebook(String name, String description, String userId) async {
    try {
      final response = await authenticatedPost(
        '/api/v1/notebooks',
        {
          'name': name,
          'description': description,
          'user_id': userId,
        }
      );

      if (response.statusCode == 201) {
        return Notebook.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to create notebook');
      }
    } catch (e) {
      _logger.error('Error in createNotebook', e);
      rethrow;
    }
  }

  Future<void> deleteNotebook(String id) async {
    try {
      final response = await authenticatedDelete('/api/v1/notebooks/$id');

      if (response.statusCode != 204) {
        throw Exception('Failed to delete notebook');
      }
    } catch (e) {
      _logger.error('Error in deleteNotebook', e);
      rethrow;
    }
  }

  Future<Notebook> updateNotebook(String id, String name, String description) async {
    try {
      final response = await authenticatedPut(
        '/api/v1/notebooks/$id',
        {
          'name': name,
          'description': description,
        }
      );

      if (response.statusCode == 200) {
        return Notebook.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to update notebook');
      }
    } catch (e) {
      _logger.error('Error in updateNotebook', e);
      rethrow;
    }
  }

  Future<Notebook> getNotebook(String id) async {
    try {
      final response = await authenticatedGet('/api/v1/notebooks/$id');
      
      if (response.statusCode == 200) {
        return Notebook.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load notebook');
      }
    } catch (e) {
      _logger.error('Error in getNotebook', e);
      rethrow;
    }
  }
}
