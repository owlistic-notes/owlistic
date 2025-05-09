import 'dart:convert';
import '../models/block.dart';
import '../utils/logger.dart';
import 'base_service.dart';

class BlockService extends BaseService {
  final Logger _logger = Logger('BlockService');

  // Fetch blocks with consistent patterns
  Future<List<Block>> fetchBlocksForNote(
    String noteId, 
    {Map<String, dynamic>? queryParams}
  ) async {
    try {
      Map<String, dynamic> params = {'note_id': noteId};
      
      if (queryParams != null) {
        params.addAll(queryParams);
      }
      
      final response = await authenticatedGet(
        '/api/v1/blocks',
        queryParameters: params,
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Block.fromJson(json)).toList();
      } else {
        _logger.error('Failed to load blocks: ${response.statusCode}, ${response.body}');
        throw Exception('Failed to load blocks: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error in fetchBlocksForNote', e);
      rethrow;
    }
  }

  Future<Block> createBlock(String noteId, dynamic content, String blockType, double order) async {
    try {
      // Convert content to proper format for API
      Map<String, dynamic> contentMap;
      if (content is String) {
        contentMap = {'text': content};
      } else if (content is Map) {
        contentMap = Map<String, dynamic>.from(content);
      } else {
        contentMap = {'text': content.toString()};
      }
      
      // Make sure metadata exists and contains _sync_source
      if (!contentMap.containsKey('metadata')) {
        contentMap['metadata'] = {'_sync_source': 'block'};
      } else if (contentMap['metadata'] is Map) {
        (contentMap['metadata'] as Map)['_sync_source'] = 'block';
      }
      
      final requestBody = {
        'note_id': noteId,
        'block_type': blockType,
        'content': contentMap,
        'order': order,
      };
      
      final response = await authenticatedPost('/api/v1/blocks', requestBody);
      
      if (response.statusCode == 201) {
        return Block.fromJson(jsonDecode(response.body));
      } else {
        _logger.error('Failed to create block: ${response.statusCode}, ${response.body}');
        throw Exception('Failed to create block: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error creating block', e);
      rethrow;
    }
  }

  Future<void> deleteBlock(String id) async {
    try {
      final response = await authenticatedDelete('/api/v1/blocks/$id');

      if (response.statusCode != 204) {
        _logger.error('Failed to delete block: ${response.statusCode}, ${response.body}');
        throw Exception('Failed to delete block: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error deleting block', e);
      rethrow;
    }
  }

  Future<Block> updateBlock(String blockId, Map<String, dynamic> content) async {
    try {
      // Create a copy of the content to avoid modifying the original
      final payload = Map<String, dynamic>.from(content);
      
      // Make sure _sync_source is inside metadata, not at the top level
      if (payload.containsKey('metadata')) {
        if (payload['metadata'] is Map) {
          (payload['metadata'] as Map)['_sync_source'] = 'block';
        } else {
          payload['metadata'] = {'_sync_source': 'block'};
        }
      } else {
        payload['metadata'] = {'_sync_source': 'block'};
      }
      
      _logger.debug('Sending update for block $blockId: $payload');
      
      final response = await authenticatedPut('/api/v1/blocks/$blockId', payload);
      
      if (response.statusCode == 200) {
        return Block.fromJson(jsonDecode(response.body));
      } else {
        _logger.error('Failed to update block: ${response.statusCode}, ${response.body}');
        throw Exception('Failed to update block: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error updating block', e);
      rethrow;
    }
  }

  Future<Block> getBlock(String id) async {
    try {
      final response = await authenticatedGet('/api/v1/blocks/$id');
      
      if (response.statusCode == 200) {
        return Block.fromJson(json.decode(response.body));
      } else {
        _logger.error('Failed to get block: ${response.statusCode}, ${response.body}');
        throw Exception('Failed to get block: ${response.statusCode}');
      }
    } catch (e) {
      _logger.error('Error getting block', e);
      rethrow;
    }
  }
}
