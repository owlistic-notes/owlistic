import 'dart:async';
import 'package:flutter/material.dart';
import '../models/block.dart';
import '../services/api_service.dart';
import 'websocket_provider.dart';
import '../utils/websocket_message_parser.dart';

class BlockProvider with ChangeNotifier {
  final Map<String, Block> _blocks = {};
  bool _isLoading = false;
  int _updateCount = 0;
  
  // WebSocket provider reference
  WebSocketProvider? _webSocketProvider;
  final Set<String> _activeNoteIds = {};
  
  // Map of timers for debounced saving
  final Map<String, Timer> _saveTimers = {};

  // Getters
  bool get isLoading => _isLoading;
  List<Block> get allBlocks => _blocks.values.toList();
  int get updateCount => _updateCount;
  Block? getBlock(String id) => _blocks[id];
  List<Block> getBlocksForNote(String noteId) => 
    _blocks.values.where((block) => block.noteId == noteId).toList()..sort((a, b) => a.order.compareTo(b.order));

  // Set the WebSocketProvider and register event listeners
  void setWebSocketProvider(WebSocketProvider provider) {
    // Skip if the provider is the same
    if (_webSocketProvider == provider) return;
    
    // Unregister from old provider if exists
    if (_webSocketProvider != null) {
      _webSocketProvider?.removeEventListener('event', 'block.updated');
      _webSocketProvider?.removeEventListener('event', 'block.created');
      _webSocketProvider?.removeEventListener('event', 'block.deleted');
      _webSocketProvider?.removeEventListener('event', 'note.updated');
    }
    
    _webSocketProvider = provider;
    
    // Register for relevant events
    provider.addEventListener('event', 'block.updated', _handleBlockUpdate);
    provider.addEventListener('event', 'block.created', _handleBlockCreate);
    provider.addEventListener('event', 'block.deleted', _handleBlockDelete);
    provider.addEventListener('event', 'note.updated', _handleNoteUpdate);
  }

  // Mark a note as active/inactive
  void activateNote(String noteId) {
    _activeNoteIds.add(noteId);
  }
  
  void deactivateNote(String noteId) {
    _activeNoteIds.remove(noteId);
    
    // Cancel any pending save timers for blocks in this note
    final blocksForNote = getBlocksForNote(noteId);
    for (final block in blocksForNote) {
      if (_saveTimers.containsKey(block.id)) {
        _saveTimers[block.id]?.cancel();
        _saveTimers.remove(block.id);
      }
    }
  }

  // Handle block update events with support for nested structures
  void _handleBlockUpdate(Map<String, dynamic> message) {
    try {
      // Use the new parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? blockId = WebSocketModelExtractor.extractBlockId(parsedMessage);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      if (blockId != null) {
        if (_blocks.containsKey(blockId)) {
          _fetchSingleBlock(blockId);
        } else if (noteId != null && _activeNoteIds.contains(noteId)) {
          _fetchSingleBlock(blockId);
        }
      }
    } catch (e) {
      print('BlockProvider: Error handling block update: $e');
    }
  }

  // Handle block create events
  void _handleBlockCreate(Map<String, dynamic> message) {
    // Get the block_id and note_id from payload.data
    if (message.containsKey('payload') && 
        message['payload'] is Map<String, dynamic> &&
        message['payload']['data'] is Map<String, dynamic>) {
      
      final data = message['payload']['data'];
      final blockId = data['block_id'];
      final noteId = data['note_id'];
      
      if (blockId != null && noteId != null && _activeNoteIds.contains(noteId)) {
        _fetchSingleBlock(blockId.toString());
      }
    }
  }

  // Handle block delete events
  void _handleBlockDelete(Map<String, dynamic> message) {
    // Get the block_id from payload.data
    if (message.containsKey('payload') && 
        message['payload'] is Map<String, dynamic> &&
        message['payload']['data'] is Map<String, dynamic>) {
      
      final data = message['payload']['data'];
      final blockId = data['block_id'];
      
      if (blockId != null && _blocks.containsKey(blockId)) {
        _blocks.remove(blockId);
        _updateCount++;
        notifyListeners();
      }
    }
  }

  // Handle note update events with support for nested structures
  void _handleNoteUpdate(Map<String, dynamic> message) {
    try {
      // Use the new parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      if (noteId != null && _activeNoteIds.contains(noteId)) {
        fetchBlocksForNote(noteId);
      }
    } catch (e) {
      print('BlockProvider: Error handling note update: $e');
    }
  }

  // Fetch a single block by ID
  Future<Block?> _fetchSingleBlock(String blockId) async {
    try {
      final block = await ApiService.getBlock(blockId);
      _blocks[blockId] = block;
      
      // Subscribe to this block
      _webSocketProvider?.subscribe('block', id: blockId);
      
      _updateCount++;
      notifyListeners();
      return block;
    } catch (error) {
      print('BlockProvider: Error fetching block $blockId: $error');
      return null;
    }
  }

  // Fetch blocks for a specific note
  Future<void> fetchBlocksForNote(String noteId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final blocks = await ApiService.fetchBlocksForNote(noteId);
      
      // Remove old blocks for this note
      _blocks.removeWhere((_, block) => block.noteId == noteId);
      
      // Add all blocks to our map
      for (var block in blocks) {
        _blocks[block.id] = block;
        
        // Subscribe to this block
        _webSocketProvider?.subscribe('block', id: block.id);
      }
      
      // Also subscribe to note's blocks as a collection
      _webSocketProvider?.subscribe('note:blocks', id: noteId);
      
      _isLoading = false;
      _updateCount++;
      notifyListeners();
    } catch (error) {
      print('BlockProvider: Error fetching blocks: $error');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // Create a new block
  Future<Block> createBlock(String noteId, String content, String type, int order) async {
    try {
      final block = await ApiService.createBlock(noteId, content, type, order);
      _blocks[block.id] = block;
      
      // Subscribe to this block
      _webSocketProvider?.subscribe('block', id: block.id);
      
      _updateCount++;
      notifyListeners();
      return block;
    } catch (error) {
      print('BlockProvider: Error creating block: $error');
      rethrow;
    }
  }

  // Delete a block
  Future<void> deleteBlock(String id) async {
    try {
      await ApiService.deleteBlock(id);
      _blocks.remove(id);
      
      // Unsubscribe from this block
      _webSocketProvider?.unsubscribe('block', id: id);
      
      _updateCount++;
      notifyListeners();
    } catch (error) {
      print('BlockProvider: Error deleting block: $error');
      rethrow;
    }
  }

  // Update a block with debouncing
  void updateBlockContent(String id, String content, {String? type, bool immediate = false}) {
    // Cancel any existing timer for this block
    if (_saveTimers.containsKey(id)) {
      _saveTimers[id]?.cancel();
    }
    
    // If the block doesn't exist, exit
    if (!_blocks.containsKey(id)) {
      return;
    }
    
    final oldBlock = _blocks[id]!;
    
    // Skip if content hasn't changed
    if (oldBlock.content == content && (type == null || type == oldBlock.type)) {
      return;
    }
    
    // Optimistically update UI immediately
    _blocks[id] = Block(
      id: id,
      content: content,
      type: type ?? oldBlock.type,
      noteId: oldBlock.noteId,
      order: oldBlock.order,
    );
    _updateCount++;
    notifyListeners();
    
    // For full updates, use debounced saving to reduce API calls
    if (immediate) {
      // If immediate, save now
      _saveBlockToBackend(id, content, type: type);
    } else {
      // Otherwise, debounce for 1 second
      _saveTimers[id] = Timer(Duration(seconds: 1), () {
        _saveBlockToBackend(id, content, type: type);
      });
    }
  }
  
  // Method to persist block changes to backend via REST API
  Future<void> _saveBlockToBackend(String id, String content, {String? type}) async {
    if (!_blocks.containsKey(id)) return;
    
    try {
      final updatedBlock = await ApiService.updateBlock(id, content, type: type);
      
      // Update local block with returned data to ensure consistency
      _blocks[id] = updatedBlock;
    } catch (error) {
      print('BlockProvider: Error saving block $id: $error');
    }
  }

  // For backward compatibility
  Future<void> updateBlock(String id, String content, {String? type}) async {
    updateBlockContent(id, content, type: type, immediate: true);
  }

  @override
  void dispose() {
    // Cancel all debounce timers
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    _saveTimers.clear();
    
    // Unregister event handlers
    if (_webSocketProvider != null) {
      _webSocketProvider?.removeEventListener('event', 'block.updated');
      _webSocketProvider?.removeEventListener('event', 'block.created');
      _webSocketProvider?.removeEventListener('event', 'block.deleted');
      _webSocketProvider?.removeEventListener('event', 'note.updated');
    }
    super.dispose();
  }
}
