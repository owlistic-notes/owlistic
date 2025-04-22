import 'dart:convert';
import '../models/block.dart';
import '../utils/logger.dart';
import 'base_service.dart';
import 'auth_service.dart';

class BlockService extends BaseService {
  final Logger _logger = Logger('BlockService');

  // Helper method to get current user ID
  Future<String?> _getCurrentUserId() async {
    final authService = AuthService();
    return authService.getCurrentUserId();
  }

  Future<List<Block>> fetchBlocksForNote(
    String noteId, 
    {Map<String, dynamic>? queryParams, String? userId}
  ) async {
    try {
      // Use provided userId or get current user ID
      userId ??= await _getCurrentUserId();
      
      // Check if userId is available
      if (userId == null || userId.isEmpty) {
        _logger.error('Cannot fetch blocks: No user ID available');
        throw Exception('User ID is required for security reasons');
      }
      
      // Build base query parameters
      Map<String, dynamic> params = {
        'note_id': noteId,
        'user_id': userId // Always include user ID
      };
      
      // Add any additional query parameters
      if (queryParams != null) {
        params.addAll(queryParams);
      }
      
      _logger.debug('Fetching blocks for note: $noteId with user: $userId');
      
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

  Future<Block> createBlock(String noteId, dynamic content, String type, int order, String userId) async {
    if (userId.isEmpty) {
      userId = (await _getCurrentUserId()) ?? '';
      if (userId.isEmpty) {
        throw Exception('User ID is required for security reasons');
      }
    }
    
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
    
    _logger.debug('Creating block for note: $noteId with user: $userId');
    
    final response = await authenticatedPost(
      '/api/v1/blocks',
      {
        'note_id': noteId,
        'content': contentMap,
        'type': type,
        'order': order,
        'user_id': userId,
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
      // Get current user ID
      String? userId = await _getCurrentUserId();
      if (userId == null) {
        throw Exception('User ID is required for security reasons');
      }
      
      final response = await authenticatedDelete(
        '/api/v1/blocks/$id',
        queryParameters: {'user_id': userId}
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
    // Get current user ID
    String? userId = await _getCurrentUserId();
    if (userId == null) {
      throw Exception('User ID is required for security reasons');
    }
    
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
      'user_id': userId, // Include user ID in request body
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
      // Get current user ID
      String? userId = await _getCurrentUserId();
      if (userId == null) {
        throw Exception('User ID is required for security reasons');
      }
      
      final response = await authenticatedGet(
        '/api/v1/blocks/$id',
        queryParameters: {'user_id': userId}
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
