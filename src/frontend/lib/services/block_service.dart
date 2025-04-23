import 'dart:convert';
import '../models/block.dart';
import '../utils/logger.dart';
import 'base_service.dart';

class BlockService extends BaseService {
  final Logger _logger = Logger('BlockService');

  Future<List<Block>> fetchBlocksForNote(
    String noteId, 
    {Map<String, dynamic>? queryParams}
  ) async {
    try {
      // Build base query parameters
      Map<String, dynamic> params = {
        'note_id': noteId,
      };
      
      // Add any additional query parameters
      if (queryParams != null) {
        params.addAll(queryParams);
      }
      
      _logger.debug('Fetching blocks for note: $noteId');
      
      final response = await authenticatedGet(
        '/api/v1/blocks',
        queryParameters: params
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Block.fromJson(json)).toList();
      } else {
        _logger.error('Failed to load blocks: Status ${response.statusCode}');
        throw Exception('Failed to load blocks: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in fetchBlocksForNote', e);
      rethrow;
    }
  }

  Future<Block> createBlock(String noteId, dynamic content, String type, int order) async {
    // Convert content to proper format for API
    Map<String, dynamic> contentMap;
    
    if (content is String) {
      try {
        contentMap = json.decode(content);
      } catch (e) {
        contentMap = {'text': content};
      }
    } else if (content is Map) {
      contentMap = Map<String, dynamic>.from(content);
    } else {
      throw ArgumentError('Content must be a String or Map');
    }
    
    _logger.debug('Creating block for note: $noteId');
    
    final response = await authenticatedPost(
      '/api/v1/blocks',
      {
        'note_id': noteId,
        'content': contentMap,
        'type': type,
        'order': order,
      }
    );
    
    if (response.statusCode == 201) {
      return Block.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create block: ${response.statusCode}');
    }
  }

  Future<void> deleteBlock(String id) async {
    try {
      final response = await authenticatedDelete(
        '/api/v1/blocks/$id'
      );

      if (response.statusCode != 204) {
        throw Exception('Failed to delete block');
      }
    } catch (e) {
      _logger.error('Error in deleteBlock', e);
      rethrow;
    }
  }

  Future<Block> updateBlock(String blockId, dynamic content, {String? type}) async {
    // Convert content to proper format for API
    Map<String, dynamic> contentMap;
    
    if (content is String) {
      try {
        contentMap = json.decode(content);
      } catch (e) {
        contentMap = {'text': content};
      }
    } else if (content is Map) {
      contentMap = Map<String, dynamic>.from(content);
    } else {
      throw ArgumentError('Content must be a String or Map');
    }
    
    final Map<String, dynamic> body = {
      'content': contentMap,
    };
    
    if (type != null) {
      body['type'] = type;
    }
    
    final response = await authenticatedPut(
      '/api/v1/blocks/$blockId',
      body
    );
    
    if (response.statusCode == 200) {
      return Block.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to update block: ${response.statusCode}');
    }
  }

  Future<Block> getBlock(String id) async {
    try {
      final response = await authenticatedGet(
        '/api/v1/blocks/$id'
      );
      
      if (response.statusCode == 200) {
        return Block.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load block');
      }
    } catch (e) {
      _logger.error('Error in getBlock', e);
      rethrow;
    }
  }
}
