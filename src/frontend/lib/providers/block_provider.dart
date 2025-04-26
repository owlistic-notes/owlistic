import 'dart:async';
import 'package:flutter/material.dart';
import '../models/block.dart';
import '../services/block_service.dart';
import '../services/auth_service.dart';
import '../services/base_service.dart';
import '../services/websocket_service.dart';
import '../utils/websocket_message_parser.dart';
import '../utils/logger.dart';
import '../services/app_state_service.dart';

class BlockProvider with ChangeNotifier {
  final Logger _logger = Logger('BlockProvider');
  final Map<String, Block> _blocks = {};
  final Map<String, List<String>> _noteBlocksMap = {}; // Maps note ID to list of block IDs
  bool _isLoading = false;
  int _updateCount = 0;
  
  // Services
  final BlockService _blockService;
  final AuthService _authService;
  final WebSocketService _webSocketService = WebSocketService();
  
  // Active notes and debouncing
  final Set<String> _activeNoteIds = {};
  final Map<String, Timer> _saveTimers = {};
  Timer? _notificationDebouncer;
  bool _hasPendingNotification = false;
  bool _isActive = false;

  // Add subscription for app state changes
  StreamSubscription? _resetSubscription;
  StreamSubscription? _connectionSubscription;
  final AppStateService _appStateService = AppStateService();

  // Add pagination state tracking
  final Map<String, Map<String, dynamic>> _paginationState = {};

  // Constructor with dependency injection
  BlockProvider({BlockService? blockService, AuthService? authService})
    : _blockService = blockService ?? ServiceLocator.get<BlockService>(),
      _authService = authService ?? ServiceLocator.get<AuthService>() {
    // Listen for app reset events
    _resetSubscription = _appStateService.onResetState.listen((_) {
      resetState();
    });
    
    // Initialize event listeners
    _initializeEventListeners();
    
    // Listen for connection state changes
    _connectionSubscription = _webSocketService.connectionStateStream.listen((connected) {
      if (connected && _isActive) {
        // Resubscribe to events when connection is established
        _subscribeToEvents();
      }
    });
  }
      
  // Getters
  bool get isLoading => _isLoading;
  List<Block> get allBlocks => _blocks.values.toList();
  int get updateCount => _updateCount;
  Block? getBlock(String id) => _blocks[id];
  
  // Initialize WebSocket event listeners
  void _initializeEventListeners() {
    _logger.info('Registering event listeners for resource.action events');
    _webSocketService.addEventListener('event', 'block.updated', _handleBlockUpdate);
    _webSocketService.addEventListener('event', 'block.created', _handleBlockCreate);
    _webSocketService.addEventListener('event', 'block.deleted', _handleBlockDelete);
    _webSocketService.addEventListener('event', 'note.updated', _handleNoteUpdate);
  }
  
  // Subscribe to events
  void _subscribeToEvents() {
    _webSocketService.subscribeToEvent('block.updated');
    _webSocketService.subscribeToEvent('block.created');
    _webSocketService.subscribeToEvent('block.deleted');
    _webSocketService.subscribeToEvent('note.updated');
    
    // Also subscribe to blocks for active notes
    for (final noteId in _activeNoteIds) {
      _webSocketService.subscribe('note:blocks', id: noteId);
    }
  }
  
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
    
    // Subscribe to events when activated
    if (_webSocketService.isConnected) {
      _subscribeToEvents();
    }
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

  // Mark a note as active/inactive
  void activateNote(String noteId) {
    _activeNoteIds.add(noteId);
    // Subscribe to blocks for this note
    if (_webSocketService.isConnected) {
      _webSocketService.subscribe('note:blocks', id: noteId);
    }
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
          _webSocketService.unsubscribe('block', id: blockId);
          
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

  // Fetch blocks for a specific note with pagination
  Future<void> fetchBlocksForNote(String noteId, {
    int page = 1, 
    int pageSize = 100,
    bool append = false, // Add append option to add blocks without replacing
    bool refresh = false
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      // If refresh is true, clear existing blocks for this note
      if (refresh) {
        // Remove old blocks for this note
        final oldBlockIds = _blocks.keys.where(
          (id) => _blocks[id]?.noteId == noteId
        ).toList();
        
        for (final id in oldBlockIds) {
          _blocks.remove(id);
        }
        
        // Clear note blocks map
        _noteBlocksMap[noteId]?.clear();
      }
      
      _logger.debug('Fetching blocks for note: $noteId (page: $page, size: $pageSize)');
      
      // Query parameters for the API
      final Map<String, dynamic> queryParams = {
        'page': page,
        'page_size': pageSize,
        'count_total': 'true'
      };
      
      // Fetch blocks from service
      final blocksResult = await _blockService.fetchBlocksForNote(
        noteId, 
        queryParams: queryParams
      );
      
      // Process pagination headers from response
      final totalCount = blocksResult.length;
      final hasMore = totalCount >= pageSize;
      
      // Update pagination state
      _paginationState[noteId] = {
        'page': page,
        'page_size': pageSize,
        'total_count': totalCount,
        'has_more': hasMore
      };
      
      _logger.debug('Fetched ${blocksResult.length} blocks for note $noteId');
      
      // Initialize note blocks list if it doesn't exist
      _noteBlocksMap[noteId] ??= [];
      
      // If not appending, clear existing blocks
      if (!append) {
        _noteBlocksMap[noteId]?.clear();
      }
      
      // Add all blocks to our maps
      for (var block in blocksResult) {
        _blocks[block.id] = block;
        
        // Add to the noteBlocksMap if not already there
        if (!(_noteBlocksMap[noteId]?.contains(block.id) ?? false)) {
          _noteBlocksMap[noteId]!.add(block.id);
        }
        
        // Subscribe to this block
        if (!_webSocketService.isSubscribed('block', id: block.id)) {
          _webSocketService.subscribe('block', id: block.id);
        }
      }
      
      // Also subscribe to note's blocks as a collection
      _webSocketService.subscribe('note:blocks', id: noteId);
      
      _isLoading = false;
      _updateCount++;
      notifyListeners();
      
      _logger.debug('Total blocks loaded for note $noteId: ${getBlocksForNote(noteId).length}');
    } catch (error) {
      _logger.error('Error fetching blocks for note $noteId', error);
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // Check if there are more blocks to load for a note
  bool hasMoreBlocks(String noteId) {
    final state = _paginationState[noteId];
    if (state == null) return true; // If no state, assume we might have more
    
    final bool hasMore = state['has_more'] ?? false;
    _logger.debug('hasMoreBlocks for note $noteId: $hasMore');
    return hasMore;
  }
  
  // Get pagination info for a note
  Map<String, dynamic> getPaginationInfo(String noteId) {
    return _paginationState[noteId] ?? {
      'page': 1,
      'page_size': 100,
      'total_count': 0,
      'has_more': false
    };
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
      _webSocketService.subscribe('block', id: blockId);
      
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
      final block = await _blockService.createBlock(noteId, content, type, order);
      
      // Subscribe to this block
      _webSocketService.subscribe('block', id: block.id);
      
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
      _webSocketService.unsubscribe('block', id: id);
      
      _logger.debug('Deleted block, waiting for event');
    } catch (error) {
      _logger.error('Error deleting block $id', error);
      rethrow;
    }
  }

  // Update a block with debouncing
  void updateBlockContent(String id, dynamic content, {
    String? type, 
    int? order, 
    bool immediate = false,
    bool updateLocalOnly = false
  }) {
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
    
    // Update local block without waiting for server response
    if (updateLocalOnly) {
      final existingBlock = _blocks[id]!;
      _blocks[id] = existingBlock.copyWith(
        content: contentMap,
        type: type ?? existingBlock.type,
        order: order ?? existingBlock.order
      );
      
      // Notify listeners immediately for UI responsiveness
      _enqueueNotification();
    }
    
    _logger.debug('Debouncing block update to server');
    
    // For full updates, use debounced saving to reduce API calls
    if (immediate) {
      // If immediate, save now
      _saveBlockToBackend(id, contentMap, type: type, order: order);
    } else {
      // Otherwise, debounce for 1 second
      _saveTimers[id] = Timer(const Duration(seconds: 1), () {
        _saveBlockToBackend(id, contentMap, type: type, order: order);
      });
    }
  }
  
  // Method to persist block changes to backend
  Future<void> _saveBlockToBackend(String id, dynamic content, {String? type, int? order}) async {
    if (!_blocks.containsKey(id)) return;
    
    try {
      _logger.debug('Saving block $id to server');
      
      // Update via BlockService
      final updatedBlock = await _blockService.updateBlock(
        id, 
        content, 
        type: type,
        order: order
      );
      
      // Update local block with returned data to ensure consistency
      // but do not notify listeners unless there's a significant change
      final existingBlock = _blocks[id]!;
      final bool hasSignificantChanges = 
          existingBlock.type != updatedBlock.type || 
          existingBlock.order != updatedBlock.order ||
          existingBlock.content.toString() != updatedBlock.content.toString();
      
      _blocks[id] = updatedBlock;
      
      if (hasSignificantChanges) {
        _enqueueNotification();
      }
      
      _logger.debug('Block $id saved successfully');
    } catch (error) {
      _logger.error('Error saving block $id', error);
    }
  }

  // For backward compatibility
  Future<void> updateBlock(String id, String content, {String? type, int? order}) async {
    updateBlockContent(id, content, type: type, order: order, immediate: true);
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
        _webSocketService.subscribe('block', id: blockId);
        
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
      _webSocketService.unsubscribe('block', id: blockId);
      
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
    _resetSubscription?.cancel();
    _connectionSubscription?.cancel();
    
    // Cancel all debounce timers
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    _saveTimers.clear();
    
    // Cancel notification debouncer
    _notificationDebouncer?.cancel();
    
    // Remove event listeners
    _webSocketService.removeEventListener('event', 'block.updated');
    _webSocketService.removeEventListener('event', 'block.created');
    _webSocketService.removeEventListener('event', 'block.deleted');
    _webSocketService.removeEventListener('event', 'note.updated');
    
    super.dispose();
  }
}
