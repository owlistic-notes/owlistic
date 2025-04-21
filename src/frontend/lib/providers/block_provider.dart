import 'dart:async';
import 'package:flutter/material.dart';
import '../models/block.dart';
import '../services/block_service.dart';
import '../services/auth_service.dart';
import '../services/base_service.dart';
import 'websocket_provider.dart';
import '../utils/websocket_message_parser.dart';
import '../utils/logger.dart';

class BlockProvider with ChangeNotifier {
  final Logger _logger = Logger('BlockProvider');
  final Map<String, Block> _blocks = {};
  final Map<String, List<String>> _noteBlocksMap = {}; // Maps note ID to list of block IDs
  bool _isLoading = false;
  int _updateCount = 0;
  
  // Services
  final BlockService _blockService;
  final AuthService _authService;
  WebSocketProvider? _webSocketProvider;
  
  // Active notes and debouncing
  final Set<String> _activeNoteIds = {};
  final Map<String, Timer> _saveTimers = {};
  Timer? _notificationDebouncer;
  bool _hasPendingNotification = false;
  bool _isActive = false;

  // Constructor with dependency injection
  BlockProvider({BlockService? blockService, AuthService? authService})
    : _blockService = blockService ?? ServiceLocator.get<BlockService>(),
      _authService = authService ?? ServiceLocator.get<AuthService>();
      
  // Getters
  bool get isLoading => _isLoading;
  List<Block> get allBlocks => _blocks.values.toList();
  int get updateCount => _updateCount;
  Block? getBlock(String id) => _blocks[id];
  
  List<Block> getBlocksForNote(String noteId) {
    // Get block IDs for this note
    final blockIds = _noteBlocksMap[noteId] ?? [];
    // Get blocks from IDs and filter out any null values
    final blocks = blockIds
        .map((id) => _blocks[id])
        .where((block) => block != null)
        .cast<Block>()
        .toList();
        
    // Sort by order
    blocks.sort((a, b) => a.order.compareTo(b.order));
    return blocks;
  }

  // Add activation/deactivation pattern
  void activate() {
    _isActive = true;
    _logger.info('BlockProvider activated');
  }

  void deactivate() {
    _isActive = false;
    _logger.info('BlockProvider deactivated');
    
    // Cancel any pending timers when deactivated
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    _saveTimers.clear();
    _notificationDebouncer?.cancel();
  }

  // Set the WebSocketProvider and register event listeners
  void setWebSocketProvider(WebSocketProvider provider) {
    // Skip if the provider is the same
    if (_webSocketProvider == provider) return;
    
    // Unregister from old provider if exists
    if (_webSocketProvider != null) {
      _unregisterEventHandlers();
    }
    
    _webSocketProvider = provider;
    _registerEventHandlers();
  }

  void _registerEventHandlers() {
    // Register for standardized resource.action events
    _logger.info('Registering event listeners for resource.action events');
    _webSocketProvider?.addEventListener('event', 'block.updated', _handleBlockUpdate);
    _webSocketProvider?.addEventListener('event', 'block.created', _handleBlockCreate);
    _webSocketProvider?.addEventListener('event', 'block.deleted', _handleBlockDelete);
    _webSocketProvider?.addEventListener('event', 'note.updated', _handleNoteUpdate);
    
    // Debug to confirm handlers are registered
    _logger.debug('Registered event handlers successfully');
  }
  
  void _unregisterEventHandlers() {
    _webSocketProvider?.removeEventListener('event', 'block.updated');
    _webSocketProvider?.removeEventListener('event', 'block.created');
    _webSocketProvider?.removeEventListener('event', 'block.deleted');
    _webSocketProvider?.removeEventListener('event', 'note.updated');
  }

  // Mark a note as active/inactive
  void activateNote(String noteId) {
    _activeNoteIds.add(noteId);
    _logger.debug('Note $noteId activated');
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
    
    // Also cancel any pending notification
    _cancelPendingNotification();
    
    _logger.debug('Note $noteId deactivated');
  }
  
  // Debounced notification mechanism to avoid rapid UI refreshes
  void _enqueueNotification() {
    _hasPendingNotification = true;
    
    // Cancel existing timer
    _notificationDebouncer?.cancel();
    
    // Create new timer that will fire the notification after the debounce period
    _notificationDebouncer = Timer(const Duration(milliseconds: 300), () {
      if (_hasPendingNotification) {
        _updateCount++;
        notifyListeners();
        _hasPendingNotification = false;
      }
    });
  }
  
  void _cancelPendingNotification() {
    _notificationDebouncer?.cancel();
    _hasPendingNotification = false;
  }

  // Handle block update events
  void _handleBlockUpdate(Map<String, dynamic> message) {
    try {
      // Use the message parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? blockId = WebSocketModelExtractor.extractBlockId(parsedMessage);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      if (blockId != null) {
        _logger.debug('Received block.updated event for block ID $blockId');
        
        // Check if we should care about this block
        bool shouldUpdate = _blocks.containsKey(blockId);
        if (!shouldUpdate && noteId != null) {
          shouldUpdate = _activeNoteIds.contains(noteId);
        }
        
        if (shouldUpdate) {
          // Use the existing _fetchSingleBlock method but don't notify immediately
          _fetchBlockById(blockId);
        }
      }
    } catch (e) {
      _logger.error('Error handling block update', e);
    }
  }

  // Handle block creation events
  void _handleBlockCreate(Map<String, dynamic> message) {
    _logger.debug('Received block.created event');
    
    try {
      // Parse message using the standard parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      
      // Extract block_id and note_id using the extractor
      final String? blockId = WebSocketModelExtractor.extractBlockId(parsedMessage);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      _logger.debug('Extracted from event: blockId=$blockId, noteId=$noteId');
      
      if (blockId != null && noteId != null) {
        _logger.debug('Will process block creation for block $blockId in note $noteId');
        
        // Check if this note is active - only process blocks for active notes
        if (_activeNoteIds.contains(noteId)) {
          _logger.debug('Note $noteId is active, will fetch new block');
          
          // Add a delay to ensure the database transaction is complete
          Future.delayed(const Duration(milliseconds: 500), () {
            // Fetch the new block
            _fetchBlockById(blockId);
          });
        } else {
          _logger.debug('Note $noteId is not active, ignoring block creation');
        }
      } else {
        _logger.warning('Missing required IDs from block creation event');
      }
    } catch (e) {
      _logger.error('Error handling block create', e);
    }
  }

  // Handle block delete events
  void _handleBlockDelete(Map<String, dynamic> message) {
    try {
      // Use the message parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? blockId = WebSocketModelExtractor.extractBlockId(parsedMessage);
      
      if (blockId != null) {
        _logger.debug('Received block.deleted event for block ID $blockId');
        if (_blocks.containsKey(blockId)) {
          final block = _blocks[blockId]!;
          final noteId = block.noteId;
          
          // Remove from blocks map
          _blocks.remove(blockId);
          
          // Remove from note blocks map
          if (_noteBlocksMap.containsKey(noteId)) {
            _noteBlocksMap[noteId]?.remove(blockId);
          }
          
          // Unsubscribe from this block
          _webSocketProvider?.unsubscribe('block', id: blockId);
          
          // Use debounced notification
          _enqueueNotification();
        }
      }
    } catch (e) {
      _logger.error('Error handling block delete', e);
    }
  }

  // Handle note update events
  void _handleNoteUpdate(Map<String, dynamic> message) {
    try {
      // Use the message parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      if (noteId != null && _activeNoteIds.contains(noteId)) {
        _logger.debug('Received note.updated event for note ID $noteId, refreshing blocks');
        fetchBlocksForNote(noteId);
      }
    } catch (e) {
      _logger.error('Error handling note update', e);
    }
  }

  // Fetch blocks for a specific note
  Future<void> fetchBlocksForNote(String noteId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final blocks = await _blockService.fetchBlocksForNote(noteId);
      
      // Initialize note blocks list if it doesn't exist
      _noteBlocksMap[noteId] ??= [];
      
      // Clear existing note blocks in the map
      _noteBlocksMap[noteId]?.clear();
      
      // Remove old blocks for this note
      final oldBlockIds = _blocks.keys.where(
        (id) => _blocks[id]?.noteId == noteId
      ).toList();
      
      for (final id in oldBlockIds) {
        _blocks.remove(id);
      }
      
      // Add all blocks to our maps
      for (var block in blocks) {
        _blocks[block.id] = block;
        
        // Also add to the noteBlocksMap
        _noteBlocksMap[noteId]!.add(block.id);
        
        // Subscribe to this block
        _webSocketProvider?.subscribe('block', id: block.id);
      }
      
      // Also subscribe to note's blocks as a collection
      _webSocketProvider?.subscribe('note:blocks', id: noteId);
      
      _isLoading = false;
      _updateCount++;
      notifyListeners();
      
      _logger.debug('Fetched ${blocks.length} blocks for note $noteId');
    } catch (error) {
      _logger.error('Error fetching blocks for note $noteId', error);
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // Fetch a single block by ID
  Future<Block?> fetchBlockById(String blockId) async {
    try {
      _logger.debug('Public fetchBlockById for $blockId');
      return await _fetchBlockById(blockId);
    } catch (error) {
      _logger.error('Error in public fetchBlockById: $blockId', error);
      return null;
    }
  }
  
  // Internal method to fetch and store a block
  Future<Block?> _fetchBlockById(String blockId) async {
    try {
      _logger.debug('Fetching block with ID $blockId');
      
      // Use BlockService to get the block
      final block = await _blockService.getBlock(blockId);
      
      // Log the retrieved block details
      _logger.debug('Successfully retrieved block: ID=${block.id}, Type=${block.type}, NoteID=${block.noteId}');
      
      // Add to our blocks map
      _blocks[blockId] = block;
      
      // Update note blocks map
      final noteId = block.noteId;
      _noteBlocksMap[noteId] ??= [];
      if (!_noteBlocksMap[noteId]!.contains(blockId)) {
        _noteBlocksMap[noteId]!.add(blockId);
      }
      
      // Subscribe to this block
      _webSocketProvider?.subscribe('block', id: blockId);
      
      // Use debounced notification
      _enqueueNotification();
      
      return block;
    } catch (error) {
      _logger.error('Error fetching block $blockId', error);
      return null;
    }
  }

  // Create a new block
  Future<Block> createBlock(String noteId, dynamic content, String type, int order) async {
    try {
      // Get user ID from auth service directly
      final currentUser = await _authService.getUserProfile();
      final userId = currentUser?.id ?? '';
      
      // Create block on server
      final block = await _blockService.createBlock(noteId, content, type, order, userId);
      
      // Subscribe to this block
      _webSocketProvider?.subscribe('block', id: block.id);
      
      _logger.debug('Created new block of type $type in note $noteId, waiting for event');
      return block;
    } catch (error) {
      _logger.error('Error creating block in note $noteId', error);
      rethrow;
    }
  }

  // Delete a block
  Future<void> deleteBlock(String id) async {
    try {
      final block = _blocks[id];
      if (block == null) {
        _logger.warning('Attempted to delete non-existent block: $id');
        return;
      }
      
      // Delete block on server
      await _blockService.deleteBlock(id);
      
      // Unsubscribe from this block
      _webSocketProvider?.unsubscribe('block', id: id);
      
      _logger.debug('Deleted block, waiting for event');
    } catch (error) {
      _logger.error('Error deleting block $id', error);
      rethrow;
    }
  }

  // Update a block with debouncing
  void updateBlockContent(String id, dynamic content, {String? type, bool immediate = false}) {
    // Cancel any existing timer for this block
    if (_saveTimers.containsKey(id)) {
      _saveTimers[id]?.cancel();
    }
    
    // If the block doesn't exist, exit
    if (!_blocks.containsKey(id)) {
      _logger.warning('Attempted to update non-existent block: $id');
      return;
    }
    
    // Process content to proper format
    Map<String, dynamic> contentMap;
    if (content is String) {
      // Legacy string content - wrap in a map
      contentMap = {'text': content};
    } else if (content is Map) {
      // Already a map - use directly
      contentMap = Map<String, dynamic>.from(content);
    } else {
      _logger.error('Unsupported content type: ${content.runtimeType}');
      return;
    }
    
    _logger.debug('Sending block update to server, waiting for event');
    
    // For full updates, use debounced saving to reduce API calls
    if (immediate) {
      // If immediate, save now
      _saveBlockToBackend(id, contentMap, type: type);
    } else {
      // Otherwise, debounce for 1 second
      _saveTimers[id] = Timer(const Duration(seconds: 1), () {
        _saveBlockToBackend(id, contentMap, type: type);
      });
    }
  }
  
  // Method to persist block changes to backend
  Future<void> _saveBlockToBackend(String id, dynamic content, {String? type}) async {
    if (!_blocks.containsKey(id)) return;
    
    try {
      // Update via BlockService
      final updatedBlock = await _blockService.updateBlock(
        id, 
        content, 
        type: type
      );
      
      // Update local block with returned data to ensure consistency
      _blocks[id] = updatedBlock;
    } catch (error) {
      _logger.error('Error saving block $id', error);
    }
  }

  // For backward compatibility
  Future<void> updateBlock(String id, String content, {String? type}) async {
    updateBlockContent(id, content, type: type, immediate: true);
  }

  // Method to handle block creation events
  Future<void> addBlockFromEvent(String blockId) async {
    try {
      _logger.debug('Adding block from event: $blockId');
      final block = await _blockService.getBlock(blockId);
      
      // Check if block exists and if this is a block for an active note
      if (block != null && _activeNoteIds.contains(block.noteId)) {
        // Add to blocks map
        _blocks[blockId] = block!;
        
        // Update note blocks map
        _noteBlocksMap[block.noteId] ??= [];
        if (!_noteBlocksMap[block.noteId]!.contains(blockId)) {
          _noteBlocksMap[block.noteId]!.add(blockId);
        }
        
        // Subscribe to this block
        _webSocketProvider?.subscribe('block', id: blockId);
        
        // Use debounced notification
        _enqueueNotification();
        
        _logger.info('Successfully added block $blockId from event');
      } else {
        _logger.debug('Block $blockId belongs to inactive note ${block?.noteId}, not adding');
      }
    } catch (error) {
      _logger.error('Error adding block from event', error);
    }
  }
  
  // Method to fetch a block from a WebSocket event
  Future<void> fetchBlockFromEvent(String blockId) async {
    try {
      _logger.debug('Fetching block from event: $blockId');
      
      // Use the existing _fetchBlockById method
      final block = await _fetchBlockById(blockId);
      
      if (block != null) {
        _logger.info('Successfully fetched block $blockId from event');
      }
    } catch (error) {
      _logger.error('Error fetching block from event', error);
    }
  }
  
  // Method to handle block deletion events
  void handleBlockDeleted(String blockId) {
    _logger.debug('Handling block deletion: $blockId');
    
    // Find the block to get its note ID
    if (_blocks.containsKey(blockId)) {
      final block = _blocks[blockId]!;
      final noteId = block.noteId;
      
      // Remove from blocks map
      _blocks.remove(blockId);
      
      // Remove from note blocks map
      if (_noteBlocksMap.containsKey(noteId)) {
        _noteBlocksMap[noteId]!.remove(blockId);
      }
      
      // Unsubscribe from this block
      _webSocketProvider?.unsubscribe('block', id: blockId);
      
      // Use debounced notification
      _enqueueNotification();
      
      _logger.info('Successfully removed block $blockId');
    } else {
      _logger.debug('Block $blockId not found, nothing to remove');
    }
  }

  // Reset state on logout
  void resetState() {
    _logger.info('Resetting BlockProvider state');
    
    // Cancel any pending timers
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    _saveTimers.clear();
    _notificationDebouncer?.cancel();
    
    // Clear data
    _blocks.clear();
    _noteBlocksMap.clear();
    _activeNoteIds.clear();
    _isActive = false;
    
    notifyListeners();
  }

  @override
  void dispose() {
    // Cancel all debounce timers
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    _saveTimers.clear();
    
    // Cancel notification debouncer
    _notificationDebouncer?.cancel();
    
    // Unregister event handlers
    _unregisterEventHandlers();
    
    super.dispose();
  }
}
