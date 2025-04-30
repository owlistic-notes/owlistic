import 'dart:convert';
import '../models/block.dart';
import '../utils/logger.dart';
import 'base_service.dart';

class BlockService extends BaseService {
  final Logger _logger = Logger('BlockService');

  // Enhance fetchBlocksForNote to support pagination
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
      
      _logger.debug('Fetching blocks for note: $noteId with params: $params');
      
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

  Future<Block> createBlock(String noteId, dynamic content, String type, double order) async {
    // Convert content to proper format for API
    Map<String, dynamic> contentMap;
    Map<String, dynamic> metadata = {};
    
    if (content is String) {
      try {
        contentMap = json.decode(content);
      } catch (e) {
        contentMap = {'text': content};
      }
    } else if (content is Map) {
      contentMap = Map<String, dynamic>.from(content);
      
      // Check for metadata or styling elements that need to be extracted
      if (contentMap.containsKey('blockType')) {
        metadata['blockType'] = contentMap['blockType'];
        contentMap.remove('blockType');
      }
      
      if (contentMap.containsKey('raw_markdown')) {
        metadata['raw_markdown'] = contentMap['raw_markdown'];
        contentMap.remove('raw_markdown');
      }
    } else {
      throw ArgumentError('Content must be a String or Map');
    }
    
    _logger.debug('Creating block for note: $noteId');
    
    final Map<String, dynamic> requestBody = {
      'note_id': noteId,
      'content': contentMap,
      'type': type,
      'order': order,
    };
    
    // Add metadata if we have any
    if (metadata.isNotEmpty) {
      requestBody['metadata'] = metadata;
    }
    
    final response = await authenticatedPost(
      '/api/v1/blocks',
      requestBody
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

  Future<Block> updateBlock(String blockId, dynamic content, {String? type, double? order, Map<String, dynamic>? metadata}) async {
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
      
      // Ensure there are no non-serializable objects
      contentMap = _ensureJsonSerializable(contentMap);
    } else {
      throw ArgumentError('Content must be a String or Map');
    }
    
    // If metadata is provided separately, sanitize and add it to the content object
    if (metadata != null && metadata.isNotEmpty) {
      Map<String, dynamic> sanitizedMetadata = _ensureJsonSerializable(metadata);
      contentMap['metadata'] = sanitizedMetadata;
    }
    
    final Map<String, dynamic> body = {
      'content': contentMap,
    };
    
    if (type != null) {
      body['type'] = type;
    }
    
    if (order != null) {
      body['order'] = order;
    }
    
    _logger.debug('Sending block update: $body');
    
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
  
  // Helper method to ensure all data is JSON serializable
  Map<String, dynamic> _ensureJsonSerializable(Map<String, dynamic> data) {
    Map<String, dynamic> result = {};
    
    data.forEach((key, value) {
      if (value == null || value is String || value is num || value is bool) {
        // These types are already JSON serializable
        result[key] = value;
      } else if (value is List) {
        // Convert list items to JSON serializable forms
        List sanitizedList = [];
        for (var item in value) {
          if (item == null || item is String || item is num || item is bool) {
            sanitizedList.add(item);
          } else if (item is Map) {
            sanitizedList.add(_ensureJsonSerializable(Map<String, dynamic>.from(item)));
          } else {
            // Convert unknown types to string
            sanitizedList.add(item.toString());
          }
        }
        result[key] = sanitizedList;
      } else if (value is Map) {
        // Recursively sanitize nested maps
        result[key] = _ensureJsonSerializable(Map<String, dynamic>.from(value));
      } else {
        // Convert anything else to string
        result[key] = value.toString();
      }
    });
    
    return result;
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
