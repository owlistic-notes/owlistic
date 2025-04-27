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
    // Subscribe to standard block event types
    _webSocketService.subscribeToEvent('block.updated');
    _webSocketService.subscribeToEvent('block.created');
    _webSocketService.subscribeToEvent('block.deleted');
    _webSocketService.subscribeToEvent('note.updated');
    
    // For each active note, subscribe to its blocks
    for (final noteId in _activeNoteIds) {
      // Get blocks for this note
      final blockIds = _noteBlocksMap[noteId] ?? [];
      
      // Subscribe to each block individually
      for (final blockId in blockIds) {
        // Only subscribe if not already subscribed
        if (!_webSocketService.isSubscribed('block', id: blockId)) {
          _logger.debug('Subscribing to block: $blockId in note: $noteId');
          _webSocketService.subscribe('block', id: blockId);
        }
      }
      
      // Subscribe to the note itself
      _webSocketService.subscribe('note', id: noteId);
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
    
    // Subscribe to the note itself
    if (_webSocketService.isConnected) {
      _webSocketService.subscribe('note', id: noteId);
      
      // Also subscribe to any blocks we already have for this note
      final blockIds = _noteBlocksMap[noteId] ?? [];
      for (final blockId in blockIds) {
        _webSocketService.subscribe('block', id: blockId);
      }
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

  // Handle block update events with timestamp checking
  void _handleBlockUpdate(Map<String, dynamic> message) {
    try {
      // Use the message parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? blockId = WebSocketModelExtractor.extractBlockId(parsedMessage);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      // Extract event timestamp if available
      DateTime? eventTimestamp = WebSocketModelExtractor.extractTimestamp(parsedMessage);
      
      if (blockId != null) {
        _logger.debug('Received block.updated event for block ID $blockId');
        
        // If we have the block locally, check if this update is newer
        if (_blocks.containsKey(blockId)) {
          final localBlock = _blocks[blockId]!;
          
          // Skip update if event is older than our local block
          if (eventTimestamp != null && eventTimestamp.isBefore(localBlock.updatedAt)) {
            _logger.debug('Ignoring older update for block $blockId (event: $eventTimestamp, local: ${localBlock.updatedAt})');
            return;
          }
        }
        
        // Otherwise check if we should care about this block
        bool shouldUpdate = _blocks.containsKey(blockId);
        if (!shouldUpdate && noteId != null) {
          shouldUpdate = _activeNoteIds.contains(noteId);
        }
        
        if (shouldUpdate) {
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
    } catch (e) {notifyListeners();
      _logger.error('Error handling note update', e);
    }
  }

  // Fetch blocks for a specific note with pagination
  Future<List<Block>> fetchBlocksForNote(String noteId, {
    int page = 1, 
    int pageSize = 100,
    bool append = false,
    bool refresh = false
  }) async {
    _isLoading = true;
    
    try {
      _logger.info('Fetching blocks for note $noteId, page $page, pageSize $pageSize');
      
      // Query parameters for the API
      final Map<String, dynamic> queryParams = {
        'note_id': noteId,
        'page': page,
        'page_size': pageSize,
        'count_total': 'true'
      };
      
      // Fetch blocks from service
      final blocksResult = await _blockService.fetchBlocksForNote(noteId, queryParams: queryParams);
      
      // Initialize note blocks list if it doesn't exist
      _noteBlocksMap[noteId] ??= [];
      
      // If not appending, clear existing blocks
      if (!append) {
        for (final blockId in List.from(_noteBlocksMap[noteId] ?? [])) {
          _blocks.remove(blockId);
        }
        _noteBlocksMap[noteId]?.clear();
      }
      
      // Add all blocks to maps
      for (var block in blocksResult) {
        _blocks[block.id] = block;
        if (_noteBlocksMap[noteId]?.contains(block.id) != null && !_noteBlocksMap[noteId]!.contains(block.id)) {
          _noteBlocksMap[noteId]!.add(block.id);
        }
      }
      
      // FIX: Properly set has_more based on returned count vs requested size
      final bool hasMore = blocksResult.length >= pageSize;
      _paginationState[noteId] = {
        'page': page,
        'page_size': pageSize,
        'has_more': hasMore
      };
      
      _isLoading = false;
      _updateCount++;
      notifyListeners();
      
      return blocksResult;
    } catch (error) {
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
        _logger.warning('Block $id already deleted, skipping');
        return;
      }
      
      // Remove from local maps FIRST to prevent duplicate deletion attempts
      final noteId = block.noteId;
      
      // Remove locally before server request
      _blocks.remove(id);
      if (_noteBlocksMap.containsKey(noteId)) {
        _noteBlocksMap[noteId]?.remove(id);
      }
      
      // Force UI update immediately
      _updateCount++;
      notifyListeners();
      
      // Then delete from server
      await _blockService.deleteBlock(id);
      _logger.debug('Block $id successfully deleted');
      
    } catch (error) {
      _logger.error('Error deleting block $id: $error');
    }
  }

  // Update a block with debouncing and timestamp checking
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
    
    final existingBlock = _blocks[id]!;
    final existingUpdatedAt = existingBlock.updatedAt;
    
    // Process content to proper format
    Map<String, dynamic> contentMap;
    if (content is String) {
      contentMap = {'text': content};
    } else if (content is Map) {
      contentMap = Map<String, dynamic>.from(content);
    } else {
      _logger.error('Unsupported content type: ${content.runtimeType}');
      return;
    }
    
    // Check if content actually changed to avoid unnecessary updates
    bool hasContentChanges = false;
    if (existingBlock.content.toString() != contentMap.toString() ||
        (type != null && type != existingBlock.type) ||
        (order != null && order != existingBlock.order)) {
      hasContentChanges = true;
    }
    
    if (!hasContentChanges) {
      _logger.debug('Block $id content unchanged, skipping update');
      return;
    }
    
    // Update local block without waiting for server response
    _blocks[id] = existingBlock.copyWith(
      content: contentMap,
      type: type ?? existingBlock.type,
      order: order ?? existingBlock.order
    );
    
    // Notify listeners immediately for UI responsiveness
    _enqueueNotification();
    
    // If only updating locally, don't send to backend
    if (updateLocalOnly) {
      return;
    }
    
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
      
      // Update local block with returned data without notifying
      _blocks[id] = updatedBlock;
      
      // No notification here to prevent freezing UI
      
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

  // Subscribe only to visible blocks - simplified to use only actual subscription patterns
  void subscribeToVisibleBlocks(String noteId, List<String> visibleBlockIds) {
    // Only subscribe to individual blocks that are visible
    for (final blockId in visibleBlockIds) {
      if (!_webSocketService.isSubscribed('block', id: blockId)) {
        _logger.debug('Subscribing to block: $blockId');
        _webSocketService.subscribe('block', id: blockId);
      }
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
