import 'dart:convert';
import '../models/notebook.dart';
import '../utils/logger.dart';
import 'base_service.dart';

class NotebookService extends BaseService {
  final Logger _logger = Logger('NotebookService');

  Future<List<Notebook>> fetchNotebooks({
    String? name,
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParams,
  }) async {
    try {
      // Build query parameters
      final Map<String, dynamic> params = {
        'page': page.toString(),
        'page_size': pageSize.toString(),
      };
      
      // Add name filter if provided
      if (name != null && name.isNotEmpty) {
        params['name'] = name;
      }
      
      // Add any additional query parameters
      if (queryParams != null) {
        params.addAll(queryParams);
      }
      
      _logger.debug('Fetching notebooks with params: $params');
      final response = await authenticatedGet(
        '/api/v1/notebooks',
        queryParameters: params
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _logger.debug('Notebook response data: ${data.length} notebooks received');
        
        // Log the raw response for the first notebook to debug notes issue
        if (data.isNotEmpty) {
          _logger.debug('First notebook raw data: ${json.encode(data[0])}');
        }
        
        final notebooks = data.map((json) => Notebook.fromJson(json)).toList();
                
        return notebooks;
      } else {
        _logger.error('Failed to load notebooks: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to load notebooks');
      }
    } catch (e) {
      _logger.error('Error in fetchNotebooks', e);
      rethrow;
    }
  }

  Future<Notebook> createNotebook(String name, String description) async {
    try {
      final response = await authenticatedPost(
        '/api/v1/notebooks',
        {
          'name': name,
          'description': description,
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
      final response = await authenticatedDelete(
        '/api/v1/notebooks/$id'
      );

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
      final response = await authenticatedGet(
        '/api/v1/notebooks/$id'
      );
      
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
