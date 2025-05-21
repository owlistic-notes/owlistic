import 'dart:convert';
import 'package:owlistic/models/block.dart';
import 'package:owlistic/utils/logger.dart';
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

  Future<Block> createBlock(String noteId, Map<String, dynamic> content, String blockType, double order) async {
    try {
      // Extract content and metadata from structured input
      final inputMap = Map<String, dynamic>.from(content);
      final contentMap = Map<String, dynamic>.from(inputMap['content']);
      final metadataMap = Map<String, dynamic>.from(inputMap['metadata']);
      
      final requestBody = {
        'note_id': noteId,
        'type': blockType,
        'content': contentMap,
        'metadata': metadataMap,
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
      
      // Ensure metadata structure is correct with proper sync timestamps
      Map<String, dynamic> metadataMap = {
        '_sync_source': 'block', 
        'block_id': blockId,
        'last_synced': DateTime.now().toIso8601String() // Add current timestamp
      };
      
      // If there's existing metadata, merge it but preserve our sync fields
      if (payload.containsKey('metadata')) {
        if (payload['metadata'] is Map) {
          metadataMap.addAll(Map<String, dynamic>.from(payload['metadata']));
        }
      }
      
      // Move any nested metadata from content to top-level
      if (payload.containsKey('content') && payload['content'] is Map) {
        final contentMap = Map<String, dynamic>.from(payload['content']);
        
        // Move spans to metadata if present in content
        if (contentMap.containsKey('spans')) {
          metadataMap['spans'] = contentMap['spans'];
          contentMap.remove('spans');
        }
        
        // Move any nested metadata to top-level metadata
        if (contentMap.containsKey('metadata')) {
          if (contentMap['metadata'] is Map) {
            metadataMap.addAll(Map<String, dynamic>.from(contentMap['metadata']));
          }
          contentMap.remove('metadata');
        }
        
        payload['content'] = contentMap;
      }
      
      // Update the metadata in the payload
      payload['metadata'] = metadataMap;
      
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

  Future<Block> updateTaskCompletion(String blockId, bool isCompleted) async {
  try {
    // Get existing block
    Block block = await getBlock(blockId);
    
    // Manually create update payload
    final updatedMetadata = block.metadata != null ? 
        Map<String, dynamic>.from(block.metadata!) : <String, dynamic>{};
    
    updatedMetadata['_sync_source'] = 'block';
    updatedMetadata['block_id'] = block.id;
    updatedMetadata['is_completed'] = isCompleted;
    updatedMetadata['last_synced'] = DateTime.now().toIso8601String();
    
    final payload = <String, dynamic>{
      'content': block.content,
      'metadata': updatedMetadata,
    };
    
    return await updateBlock(blockId, payload);
  } catch (e) {
    _logger.error('Error updating task completion', e);
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
