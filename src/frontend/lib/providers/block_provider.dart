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
    
    // Register for standardized resource.action events
    print('BlockProvider: Registering event listeners for resource.action events');
    provider.addEventListener('event', 'block.updated', _handleBlockUpdate);
    provider.addEventListener('event', 'block.created', _handleBlockCreate);
    provider.addEventListener('event', 'block.deleted', _handleBlockDelete);
    provider.addEventListener('event', 'note.updated', _handleNoteUpdate);
    
    // Debug to confirm handlers are registered
    print('BlockProvider: Registered event handlers successfully');
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

  // Consolidate block update handling
  void _handleBlockUpdate(Map<String, dynamic> message) {
    try {
      // Use the new parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? blockId = WebSocketModelExtractor.extractBlockId(parsedMessage);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      if (blockId != null) {
        print('BlockProvider: Received block.updated event for block ID $blockId');
        
        // Check if we should care about this block
        bool shouldUpdate = _blocks.containsKey(blockId);
        if (!shouldUpdate && noteId != null) {
          shouldUpdate = _activeNoteIds.contains(noteId);
        }
        
        if (shouldUpdate) {
          // Use the existing _fetchSingleBlock method
          _fetchSingleBlock(blockId);
        }
      }
    } catch (e) {
      print('BlockProvider: Error handling block update: $e');
    }
  }

  // Handle block create events - aligned with the _handleNoteCreate pattern
  void _handleBlockCreate(Map<String, dynamic> message) {
    print('BlockProvider: Received block.created event');
    
    try {
      // Parse message using ONLY the standard parser - no direct extraction
      final parsedMessage = WebSocketMessage.fromJson(message);
      
      // Extract block_id and note_id using ONLY the extractor
      final String? blockId = WebSocketModelExtractor.extractBlockId(parsedMessage);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      print('BlockProvider: Extracted from event: blockId=$blockId, noteId=$noteId');
      
      if (blockId != null && noteId != null) {
        print('BlockProvider: Will process block creation for block $blockId in note $noteId');
        
        // Check if this note is active - only process blocks for active notes
        if (_activeNoteIds.contains(noteId)) {
          print('BlockProvider: Note $noteId is active, will refresh with new block');
          
          // Add a delay to ensure the database transaction is complete
          Future.delayed(Duration(milliseconds: 500), () {
            // Fetch the new block
            ApiService.getBlock(blockId).then((newBlock) {
              print('BlockProvider: Successfully fetched block ${newBlock.id}');
              
              // Add to the blocks map
              _blocks[blockId] = newBlock;
              
              // Subscribe to this block
              _webSocketProvider?.subscribe('block', id: blockId);
              
              // Increment update counter to trigger UI update
              _updateCount++;
              
              // Notify listeners
              notifyListeners();
              
              print('BlockProvider: Added block to map, now have ${getBlocksForNote(noteId).length} blocks for note $noteId');
            }).catchError((error) {
              print('BlockProvider: Error fetching new block $blockId: $error');
            });
          });
        } else {
          print('BlockProvider: Note $noteId is not active, ignoring block creation');
        }
      } else {
        print('BlockProvider: Missing required IDs from block creation event');
        // Log the message structure to help debug parser issues
        print('BlockProvider: Message structure for debugging:');
        print('BlockProvider: Event type: ${parsedMessage.type}, Event: ${parsedMessage.event}');
        // Do not attempt any direct extraction, just report the problem
      }
    } catch (e) {
      print('BlockProvider: Error handling block create: $e');
    }
  }

  // Handle block delete events
  void _handleBlockDelete(Map<String, dynamic> message) {
    try {
      // Use the new parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? blockId = WebSocketModelExtractor.extractBlockId(parsedMessage);
      
      if (blockId != null) {
        print('BlockProvider: Received block.deleted event for block ID $blockId');
        if (_blocks.containsKey(blockId)) {
          _blocks.remove(blockId);
          _updateCount++;
          notifyListeners();
        }
      }
    } catch (e) {
      print('BlockProvider: Error handling block delete: $e');
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

  // Fetch a single block by ID with better logging and sorting
  Future<Block?> _fetchSingleBlock(String blockId) async {
    try {
      print('BlockProvider: Fetching block with ID $blockId');
      final block = await ApiService.getBlock(blockId);
      
      // Log the retrieved block details
      print('BlockProvider: Successfully retrieved block: ID=${block.id}, Type=${block.type}, NoteID=${block.noteId}');
      
      // Add to our _blocks map with direct assignment
      _blocks[blockId] = block;
      
      // Subscribe to this block
      _webSocketProvider?.subscribe('block', id: blockId);
      
      // Increment update counter to force UI rebuild
      _updateCount++;
      
      // Explicitly log the update
      print('BlockProvider: Added/updated block ${block.id} in cache, update counter: $_updateCount');
      
      // Check if this block belongs to an active note and log it
      if (_activeNoteIds.contains(block.noteId)) {
        print('BlockProvider: Block belongs to active note ${block.noteId}, UI should update');
        final noteBlocks = getBlocksForNote(block.noteId);
        print('BlockProvider: Note ${block.noteId} now has ${noteBlocks.length} blocks');
      }
      
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
