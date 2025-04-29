import 'dart:async';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart' hide Logger;

import '../services/block_service.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import '../services/note_service.dart';
import '../models/block.dart';
import '../models/note.dart';
import '../utils/document_builder.dart';
import '../utils/logger.dart';
import '../utils/websocket_message_parser.dart';
import '../viewmodel/note_editor_viewmodel.dart';
import '../services/app_state_service.dart';

class NoteEditorProvider with ChangeNotifier implements NoteEditorViewModel {
  final Logger _logger = Logger('NoteEditorProvider');
  
  // State variables
  bool _isLoading = false;
  bool _isInitialized = false;
  bool _isActive = false;
  String? _errorMessage;
  String? _noteId;
  int _updateCount = 0;
  
  // Current note object
  Note? _currentNote;
  
  // Injected services
  final BlockService _blockService;
  final AuthService _authService;
  final WebSocketService _webSocketService;
  final NoteService _noteService;
  final DocumentBuilder Function() _documentBuilderFactory;
  
  // Block storage
  final Map<String, Block> _blocks = {};
  final Map<String, List<String>> _noteBlocksMap = {}; // Maps note ID to list of block IDs
  
  // Document handling
  late DocumentBuilder _documentBuilder;
  
  // Active notes tracking
  final Set<String> _activeNoteIds = {};
  
  // Pagination state
  final Map<String, Map<String, dynamic>> _paginationState = {};
  
  // Debouncing mechanisms
  final Map<String, Timer> _saveTimers = {};
  Timer? _notificationDebouncer;
  bool _hasPendingNotification = false;
  
  // Event callbacks
  void Function(String blockId, dynamic content)? _onBlockContentChanged;
  void Function(List<String> blockIds)? _onMultiBlockOperation;
  void Function(String blockId)? _onBlockDeleted;
  void Function()? _onFocusLost;
  
  // Focus request tracking
  String? _focusRequestedBlockId;
  
  // App state subscriptions
  StreamSubscription? _resetSubscription;
  StreamSubscription? _connectionSubscription;
  final AppStateService _appStateService = AppStateService();
  
  // DateTime _lastEdit for debouncing
  DateTime _lastEdit = DateTime.now();
  String? _currentEditingBlockId;
  
  // Flag to prevent recursive document updates
  bool _updatingDocument = false;
  
  // Constructor with dependency injection
  NoteEditorProvider({
    required BlockService blockService,
    required AuthService authService,
    required WebSocketService webSocketService,
    required NoteService noteService,
    required DocumentBuilder Function() documentBuilderFactory,
    String? initialNoteId,
    List<Block>? initialBlocks,
    Note? initialNote,
  }) : _blockService = blockService,
       _authService = authService,
       _webSocketService = webSocketService,
       _noteService = noteService,
       _documentBuilderFactory = documentBuilderFactory,
       _noteId = initialNoteId,
       _currentNote = initialNote {
    
    // Initialize document builder
    _documentBuilder = _documentBuilderFactory();
    
    // Setup listeners
    _initializeEventListeners();
    
    // Load initial blocks if provided
    if (initialBlocks != null) {
      setBlocks(initialBlocks);
    }
    
    // Listen for app reset events
    _resetSubscription = _appStateService.onResetState.listen((_) {
      resetState();
    });
    
    // Listen for connection state changes
    _connectionSubscription = _webSocketService.connectionStateStream.listen((connected) {
      if (connected && _isActive) {
        // Resubscribe to events when connection is established
        _subscribeToEvents();
      }
    });
    
    // Mark as initialized
    _isInitialized = true;
  }
  
  // Note related methods added from NotesViewModel
  
  // Current note getter
  @override
  Note? get currentNote => _currentNote;
  
  // Fetch a note by ID
  @override
  Future<Note?> fetchNoteById(String id) async {
    try {
      _logger.debug('Fetching note with ID $id');
      
      // Use NoteService to get the note
      final Note note = await _noteService.getNote(id);
      
      // Store as current note
      _currentNote = note;
      _noteId = note.id;
      
      // Subscribe to note events
      if (_isActive) {
        _webSocketService.subscribe('note', id: note.id);
      }
      
      // Use debounced notification
      _enqueueNotification();
      
      return note;
    } catch (error) {
      _logger.error('Error fetching note $id', error);
      _errorMessage = 'Failed to fetch note: ${error.toString()}';
      notifyListeners();
      return null;
    }
  }
  
  // Update a note's title
  @override
  Future<Note> updateNoteTitle(String id, String title) async {
    try {
      _logger.info('Updating note title for $id to: $title');
      
      // Use NoteService to update the note
      final updatedNote = await _noteService.updateNote(id, title);
      
      // Update local state
      if (_currentNote?.id == id) {
        _currentNote = updatedNote;
      }
      
      // Notify listeners
      _updateCount++;
      notifyListeners();
      
      return updatedNote;
    } catch (error) {
      _logger.error('Error updating note title', error);
      _errorMessage = 'Failed to update note: ${error.toString()}';
      notifyListeners();
      throw error;
    }
  }

  // Basic getters from BaseViewModel
  @override
  bool get isLoading => _isLoading;
  
  @override
  bool get isInitialized => _isInitialized;
  
  @override
  bool get isActive => _isActive;
  
  @override
  String? get errorMessage => _errorMessage;
  
  @override
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
  
  // Note properties
  @override
  String? get noteId => _noteId;
  
  @override
  set noteId(String? value) {
    _noteId = value;
    notifyListeners();
  }
  
  @override
  List<Block> get blocks => _noteId != null ? getBlocksForNote(_noteId!) : [];

  @override
  int get updateCount => _updateCount;
  
  // Document builder access
  @override
  DocumentBuilder get documentBuilder => _documentBuilder;
  
  @override
  FocusNode get focusNode => _documentBuilder.focusNode;
  
  // Access to user-modified blocks
  @override
  Set<String> get userModifiedBlockIds => _documentBuilder.userModifiedBlockIds;
  
  // Block access methods
  @override
  Block? getBlock(String id) => _blocks[id];
  
  @override
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

  // WebSocket event handling
  void _initializeEventListeners() {
    _logger.info('Registering event listeners for block events');
    
    // Register internal handlers to WebSocketService
    _webSocketService.addEventListener('event', 'block.updated', _handleBlockUpdate);
    _webSocketService.addEventListener('event', 'block.created', _handleBlockCreate);
    _webSocketService.addEventListener('event', 'block.deleted', _handleBlockDelete);
    _webSocketService.addEventListener('event', 'note.updated', _handleNoteUpdate);
  }
  
  void _subscribeToEvents() {
    // Subscribe to standard block event types
    _webSocketService.subscribeToEvent('block.updated');
    _webSocketService.subscribeToEvent('block.created');
    _webSocketService.subscribeToEvent('block.deleted');
    _webSocketService.subscribeToEvent('note.updated');
    
    // For each active note, subscribe to its blocks
    for (final noteId in _activeNoteIds) {
      // Subscribe to the note itself
      _webSocketService.subscribe('note', id: noteId);
      
      // Get blocks for this note
      final blockIds = _noteBlocksMap[noteId] ?? [];
      
      // Subscribe to each block individually
      for (final blockId in blockIds) {
        if (!_webSocketService.isSubscribed('block', id: blockId)) {
          _webSocketService.subscribe('block', id: blockId);
        }
      }
    }
  }
  
  // Standardized activate/deactivate methods
  @override
  void activate() {
    _isActive = true;
    _logger.info('NoteEditorProvider activated');
    
    // Register document event listeners
    _documentBuilder.addDocumentStructureListener(_documentStructureChangeListener);
    _documentBuilder.addDocumentContentListener(_documentChangeListener);
    _documentBuilder.focusNode.addListener(_handleFocusChange);
    
    // Subscribe to events when activated
    if (_webSocketService.isConnected) {
      _subscribeToEvents();
    }
  }
  
  @override
  void deactivate() {
    _isActive = false;
    _logger.info('NoteEditorProvider deactivated');
    
    // Commit all content before deactivating
    commitAllContent();
    
    // Remove listeners
    _documentBuilder.removeDocumentStructureListener(_documentStructureChangeListener);
    _documentBuilder.removeDocumentContentListener(_documentChangeListener);
    _documentBuilder.focusNode.removeListener(_handleFocusChange);
    
    // Cancel any pending timers when deactivated
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    _saveTimers.clear();
    _notificationDebouncer?.cancel();
  }
  
  // Document structure change listener
  void _documentStructureChangeListener(_) {
    if (_updatingDocument) return;
    
    _documentBuilder.checkDocumentStructureChanges(
      onNewNodeCreated: _handleNewNodeCreated,
      onNodeDeleted: _handleNodeDeleted,
    );
  }
  
  // Handle newly created nodes
  void _handleNewNodeCreated(String nodeId) {
    if (!_documentBuilder.shouldCreateBlockForNode(nodeId)) {
      return;
    }
    
    // Get the node from the document
    final node = _documentBuilder.document.getNodeById(nodeId);
    if (node == null) {
      _logger.warning('Could not find node $nodeId in document');
      return;
    }
    
    // Create server-side block for this node
    _createBlockForNode(nodeId, node);
  }
  
  // Handle deleted nodes
  void _handleNodeDeleted(String nodeId) {
    // Check if this node was mapped to a block
    final blockId = _documentBuilder.nodeToBlockMap[nodeId];
    if (blockId == null) {
      _logger.debug('Node $nodeId wasn\'t mapped to a block, nothing to delete');
      return;
    }
    
    // Check if this is a node we were trying to create
    if (_documentBuilder.uncommittedNodes.containsKey(nodeId)) {
      _logger.info('Node $nodeId was deleted before it was committed, removing from uncommitted nodes');
      _documentBuilder.uncommittedNodes.remove(nodeId);
      return;
    }
    
    _logger.info('Node $nodeId was deleted, will delete block $blockId on server');
    
    // Remove from our mappings
    _documentBuilder.nodeToBlockMap.remove(nodeId);
    
    // Remove from blocks list if it exists
    _blocks.remove(blockId);
    
    // Remove from note blocks map
    if (_noteId != null && _noteBlocksMap.containsKey(_noteId)) {
      _noteBlocksMap[_noteId!]?.remove(blockId);
    }
    
    // Delete from server
    _blockService.deleteBlock(blockId);
    
    // Notify listeners
    _enqueueNotification();
  }
  
  // Create a server block for a new node created in the editor
  Future<void> _createBlockForNode(String nodeId, DocumentNode node) async {
    try {
      _logger.info('Creating block for new node $nodeId');
      
      if (noteId == null) {
        _logger.error('Cannot create block: noteId is null');
        return;
      }
      
      // Determine block type based on node
      String blockType = 'text';
      if (node is ParagraphNode) {
        final blockTypeAttr = node.metadata?['blockType'];
        if (blockTypeAttr == 'heading') {
          blockType = 'heading';
        } else if (blockTypeAttr == 'code') {
          blockType = 'code';
        }
      } else if (node is ListItemNode) {
        blockType = 'checklist';
      }
      
      // Extract content from node in the format needed by API
      final extractedData = _extractNodeContentForApi(node);
      final content = extractedData['content'] as Map<String, dynamic>;
      final metadata = extractedData['metadata'] as Map<String, dynamic>?;
      
      // Calculate a fractional order value using the document builder
      double order = await _documentBuilder.calculateOrderForNewNode(nodeId, blocks);
      
      _logger.debug('Creating block of type $blockType with fractional order $order');
      
      // Create block through BlockService
      final block = await _blockService.createBlock(
        noteId!, 
        content,
        blockType,
        order
      );
      
      // Update our mappings
      _documentBuilder.nodeToBlockMap[nodeId] = block.id;
      _blocks[block.id] = block;
      
      // Add to note blocks map
      _noteBlocksMap[noteId!] ??= [];
      if (!_noteBlocksMap[noteId!]!.contains(block.id)) {
        _noteBlocksMap[noteId!]!.add(block.id);
      }
      
      // Remove from uncommitted nodes
      _documentBuilder.uncommittedNodes.remove(nodeId);
      
      // Subscribe to this block
      _webSocketService.subscribe('block', id: block.id);
      
      // Notify listeners
      _enqueueNotification();
      
      _logger.info('Successfully created block ${block.id} for node $nodeId');
    } catch (e) {
      _logger.error('Failed to create block for node $nodeId: $e');
      // Keep in uncommitted nodes list to try again later
    }
  }
  
  // Extract content from a node in the format expected by the API
  Map<String, dynamic> _extractNodeContentForApi(DocumentNode node) {
    Map<String, dynamic> content = {};
    Map<String, dynamic> metadata = {};
    
    if (node is ParagraphNode) {
      // Basic text content
      content['text'] = node.text.toPlainText();
      
      // Extract spans/formatting information
      final spans = _documentBuilder.extractSpansFromAttributedText(node.text);
      if (spans.isNotEmpty) {
        content['spans'] = spans;
      }
      
      // Add metadata based on node.metadata
      if (node.metadata != null && node.metadata!.isNotEmpty) {
        final blockType = node.metadata!['blockType'];
        if (blockType != null) {
          metadata['blockType'] = blockType;
          
          // Add type-specific properties
          if (blockType == 'heading') {
            content['level'] = node.metadata!['headingLevel'] ?? 1;
          } else if (blockType == 'code') {
            content['language'] = node.metadata!['language'] ?? 'plain';
          }
        }
      }
    } else if (node is ListItemNode) {
      content['text'] = node.text.toPlainText();
      content['checked'] = node.type == ListItemType.ordered;
      metadata['blockType'] = 'listItem';
      
      // Extract spans for list items as well
      final spans = _documentBuilder.extractSpansFromAttributedText(node.text);
      if (spans.isNotEmpty) {
        content['spans'] = spans;
      }
    }
    
    return {
      'content': content,
      'metadata': metadata.isEmpty ? null : metadata
    };
  }
  
  // DocumentChangeListener implementation for content changes
  void _documentChangeListener(_) {
    if (!_updatingDocument) {
      _handleDocumentChange();
    }
  }
  
  // Track which block is being edited and schedule updates
  void _handleDocumentChange() {
    // Get the node that's currently being edited
    final selection = _documentBuilder.composer.selection;
    if (selection == null) return;
    
    // Get node ID from selection
    final nodeId = selection.extent.nodeId;
    if (nodeId == null) return;
    
    // Find the block ID for this node
    final blockId = _documentBuilder.nodeToBlockMap[nodeId];
    if (blockId == null) return;
    
    // Set the current editing block
    _currentEditingBlockId = blockId;
    _lastEdit = DateTime.now();
    
    // Mark the block as modified by the user
    _documentBuilder.markBlockAsModified(blockId);
    
    // Debounce updates to avoid too many API calls
    Future.delayed(const Duration(milliseconds: 500), () {
      // Only update if this is still the most recent edit
      if (DateTime.now().difference(_lastEdit).inMilliseconds >= 500 && 
          blockId == _currentEditingBlockId) {
        _commitBlockContentChange(nodeId);
      }
    });
  }
  
  // Commit changes for a specific node
  void _commitBlockContentChange(String nodeId) {
    // Find block ID for this node
    final blockId = _documentBuilder.nodeToBlockMap[nodeId];
    if (blockId == null) return;
    
    // Find node in document
    final node = _documentBuilder.document.getNodeById(nodeId);
    if (node == null) return;
    
    // Find the block to extract content against
    final block = getBlock(blockId);
    if (block == null) return;
    
    // Extract content from node with proper formatting
    final content = _documentBuilder.extractContentFromNode(node, blockId, block);
    
    // Send content update with formats included
    updateBlockContent(blockId, content, immediate: true);
  }
  
  // Handle focus change
  void _handleFocusChange() {
    if (!_documentBuilder.focusNode.hasFocus) {
      // Commit any pending changes
      commitAllContent();
      
      // Call the focus lost handler if provided
      _onFocusLost?.call();
    }
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
  
  // WebSocket event handlers
  void _handleBlockUpdate(Map<String, dynamic> message) {
    try {
      // Use the message parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? blockId = WebSocketModelExtractor.extractBlockId(parsedMessage);
      final String? eventNoteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      // Extract event timestamp if available
      DateTime? eventTimestamp = WebSocketModelExtractor.extractTimestamp(parsedMessage);
      
      if (blockId != null) {
        _logger.debug('Received block.updated event for block ID $blockId');
        
        // If we have the block locally, check if this update is newer
        if (_blocks.containsKey(blockId)) {
          final localBlock = _blocks[blockId]!;
          
          // Skip update if event is older than our local block
          if (eventTimestamp != null && eventTimestamp.isBefore(localBlock.updatedAt)) {
            _logger.debug('Ignoring older update for block $blockId');
            return;
          }
        }
        
        // Check if we should care about this block
        bool shouldUpdate = _blocks.containsKey(blockId);
        if (!shouldUpdate && eventNoteId != null) {
          shouldUpdate = _activeNoteIds.contains(eventNoteId);
        }
        
        if (shouldUpdate) {
          fetchBlockById(blockId).then((block) {
            // After fetching, update document if needed
            if (block != null) {
              _updateDocumentWithBlock(block);
              _enqueueNotification();
            }
          });
        }
      }
    } catch (e) {
      _logger.error('Error handling block update', e);
    }
  }
  
  void _handleBlockCreate(Map<String, dynamic> message) {
    try {
      // Use the message parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      
      // Extract block_id and note_id using the extractor
      final String? blockId = WebSocketModelExtractor.extractBlockId(parsedMessage);
      final String? eventNoteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      if (blockId != null && eventNoteId != null && 
          (_noteId == eventNoteId || _activeNoteIds.contains(eventNoteId))) {
        // Add a delay to ensure the database transaction is complete
        Future.delayed(const Duration(milliseconds: 500), () {
          fetchBlockById(blockId).then((block) {
            if (block != null) {
              // Add the new block to the document
              _addBlockToDocument(block);
              _enqueueNotification();
            }
          });
        });
      }
    } catch (e) {
      _logger.error('Error handling block create', e);
    }
  }

  void _handleBlockDelete(Map<String, dynamic> message) {
    try {
      // Use the message parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? blockId = WebSocketModelExtractor.extractBlockId(parsedMessage);
      
      if (blockId != null && _blocks.containsKey(blockId)) {
        // Remove from blocks map
        final block = _blocks[blockId]!;
        final blockNoteId = block.noteId;
        
        // Remove from blocks map
        _blocks.remove(blockId);
        
        // Remove from note blocks map
        if (_noteBlocksMap.containsKey(blockNoteId)) {
          _noteBlocksMap[blockNoteId]?.remove(blockId);
        }
        
        // Find and remove the node from document
        String? nodeToRemove;
        _documentBuilder.nodeToBlockMap.forEach((nodeId, mappedBlockId) {
          if (mappedBlockId == blockId) {
            nodeToRemove = nodeId;
          }
        });
        
        if (nodeToRemove != null) {
          _updatingDocument = true;
          try {
            _documentBuilder.document.deleteNode(nodeToRemove!);
            _documentBuilder.nodeToBlockMap.remove(nodeToRemove);
          } finally {
            _updatingDocument = false;
          }
        }
        
        // Unsubscribe from this block
        _webSocketService.unsubscribe('block', id: blockId);
        
        // Use debounced notification
        _enqueueNotification();
      }
    } catch (e) {
      _logger.error('Error handling block delete', e);
    }
  }

  void _handleNoteUpdate(Map<String, dynamic> message) {
    try {
      // Use the message parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? eventNoteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      if (eventNoteId != null && (_noteId == eventNoteId || _activeNoteIds.contains(eventNoteId))) {
        _logger.debug('Received note.updated event for note ID $eventNoteId, refreshing blocks');
        fetchBlocksForNote(eventNoteId);
      }
    } catch (e) {
      _logger.error('Error handling note update', e);
    }
  }
  
  // Update a document with a block received from server
  void _updateDocumentWithBlock(Block block) {
    // First find any existing nodes for this block
    List<String> existingNodeIds = [];
    _documentBuilder.nodeToBlockMap.forEach((nodeId, blockId) {
      if (blockId == block.id) {
        existingNodeIds.add(nodeId);
      }
    });
    
    // If no existing nodes, this block needs to be added
    if (existingNodeIds.isEmpty) {
      _addBlockToDocument(block);
      return;
    }
    
    // Update each node with this block's content
    for (final nodeId in existingNodeIds) {
      final node = _documentBuilder.document.getNodeById(nodeId);
      if (node == null) continue;
      
      // Check if we should update this block from server
      if (_documentBuilder.shouldUpdateFromServer(block.id, block)) {
        _updatingDocument = true;
        try {
          // Create new nodes from block
          final nodes = _documentBuilder.createNodesFromBlock(block);
          if (nodes.isNotEmpty) {
            // Replace the old node with the new one
            final index = _documentBuilder.document.getNodeIndexById(nodeId) ?? -1;
            if (index >= 0) {
              _documentBuilder.document.replaceNodeById(nodeId, nodes.first);
              _documentBuilder.nodeToBlockMap[nodes.first.id] = block.id;
            }
          }
        } finally {
          _updatingDocument = false;
        }
      }
    }
    
    // Update the block in our storage
    _blocks[block.id] = block;
  }
  
  // Add a block to the document
  void _addBlockToDocument(Block block) {
    // Only add if this block belongs to the current note
    if (_noteId != block.noteId) return;
    
    // Add to blocks map
    _blocks[block.id] = block;
    
    // Update note blocks map
    _noteBlocksMap[block.noteId] ??= [];
    if (!_noteBlocksMap[block.noteId]!.contains(block.id)) {
      _noteBlocksMap[block.noteId]!.add(block.id);
    }
    
    // Create nodes and add to document
    _updatingDocument = true;
    try {
      final nodes = _documentBuilder.createNodesFromBlock(block);
      for (final node in nodes) {
        _documentBuilder.document.add(node);
        _documentBuilder.nodeToBlockMap[node.id] = block.id;
      }
    } finally {
      _updatingDocument = false;
    }
    
    // Subscribe to this block
    _webSocketService.subscribe('block', id: block.id);
  }

  // Implementation of NoteEditorViewModel methods
  
  @override
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
      
      // If not appending, clear existing blocks for this note
      if (!append) {
        for (final blockId in List.from(_noteBlocksMap[noteId] ?? [])) {
          _blocks.remove(blockId);
        }
        _noteBlocksMap[noteId]?.clear();
      }
      
      // Track if we received any new blocks
      int newBlockCount = 0;
      
      // Add all blocks to maps, tracking which ones are actually new
      for (var block in blocksResult) {
        // Check if this block is already in our map
        final isNewBlock = !_blocks.containsKey(block.id);
        
        _blocks[block.id] = block;
        if (!_noteBlocksMap[noteId]!.contains(block.id)) {
          _noteBlocksMap[noteId]!.add(block.id);
          newBlockCount++;
        }
      }
      
      // IMPORTANT FIX: Update pagination state based on if we got any new blocks
      // If we got zero new blocks, we're at the end of the data
      final bool hasMore = blocksResult.isNotEmpty && newBlockCount > 0;
      _paginationState[noteId] = {
        'page': page,
        'page_size': pageSize,
        'has_more': hasMore
      };
      
      _logger.debug('Pagination state updated for $noteId: hasMore=$hasMore, newBlockCount=$newBlockCount');
      
      // If this is the current note and not appending, update document
      if (_noteId == noteId && !append) {
        setBlocks(blocksResult);
      } else if (_noteId == noteId && append) {
        // If appending to current note, add blocks to document
        addBlocks(blocksResult);
      }
      
      _isLoading = false;
      _updateCount++;
      notifyListeners();
      
      return blocksResult;
    } catch (error) {
      _isLoading = false;
      _errorMessage = error.toString();
      notifyListeners();
      rethrow;
    }
  }
  
  @override
  Future<Block?> fetchBlockById(String blockId) async {
    try {
      _logger.debug('Fetching block with ID $blockId');
      
      // Use BlockService to get the block
      final Block? block = await _blockService.getBlock(blockId);
      
      if (block == null) {
        _logger.warning('Block $blockId not found on server');
        return null;
      }
      
      // Add to our blocks map
      _blocks[blockId] = block;
      
      // Update note blocks map
      final String blockNoteId = block.noteId;
      _noteBlocksMap[blockNoteId] ??= [];
      if (!_noteBlocksMap[blockNoteId]!.contains(blockId)) {
        _noteBlocksMap[blockNoteId]!.add(blockId);
      }
      
      // Subscribe to this block
      _webSocketService.subscribe('block', id: blockId);
      
      // Update document if this block belongs to the current note
      if (_noteId == blockNoteId) {
        _updateDocumentWithBlock(block);
      }
      
      // Use debounced notification
      _enqueueNotification();
      
      return block;
    } catch (error) {
      _logger.error('Error fetching block $blockId', error);
      return null;
    }
  }
  
  @override
  Future<Block> createBlock(String type) async {
    _logger.info('Creating new block of type: $type');
    
    if (_noteId == null) {
      throw Exception('Cannot create block: noteId is null');
    }
    
    // Calculate order for new block 
    double order = 1.0;
    if (blocks.isNotEmpty) {
      // Place it at the end by default
      order = blocks.map((b) => b.order).reduce((a, b) => a > b ? a : b) + 1.0;
    }
    
    // Initial content based on type
    Map<String, dynamic> content = {'text': ''};
    if (type == 'heading') {
      content['level'] = 1;
    } else if (type == 'checklist') {
      content['checked'] = false;
    }
    
    // Create block on server
    final block = await _blockService.createBlock(
      _noteId!,
      content,
      type,
      order
    );
    
    // Add to local state
    _blocks[block.id] = block;
    
    // Add to note blocks map
    _noteBlocksMap[_noteId!] ??= [];
    _noteBlocksMap[_noteId!]!.add(block.id);
    
    // Add to document
    _addBlockToDocument(block);
    
    // Notify listeners
    _enqueueNotification();
    
    return block;
  }
  
  @override
  Future<void> deleteBlock(String blockId) async {
    try {
      final block = _blocks[blockId];
      if (block == null) {
        _logger.warning('Block $blockId already deleted, skipping');
        return;
      }
      
      // Find nodes belonging to this block
      final nodesToDelete = <String>[];
      _documentBuilder.nodeToBlockMap.forEach((nodeId, mappedBlockId) {
        if (mappedBlockId == blockId) {
          nodesToDelete.add(nodeId);
        }
      });
      
      // Delete each node from the document
      _updatingDocument = true;
      try {
        for (final nodeId in nodesToDelete) {
          final node = _documentBuilder.document.getNodeById(nodeId);
          if (node != null) {
            _documentBuilder.document.deleteNode(nodeId);
          }
          _documentBuilder.nodeToBlockMap.remove(nodeId);
        }
      } finally {
        _updatingDocument = false;
      }
      
      // Remove from local maps
      final noteId = block.noteId;
      _blocks.remove(blockId);
      if (_noteBlocksMap.containsKey(noteId)) {
        _noteBlocksMap[noteId]?.remove(blockId);
      }
      
      // Force UI update immediately
      _updateCount++;
      notifyListeners();
      
      // Delete from server
      await _blockService.deleteBlock(blockId);
      
      // Unsubscribe from this block
      _webSocketService.unsubscribe('block', id: blockId);
      
      _logger.debug('Block $blockId successfully deleted');
    } catch (error) {
      _logger.error('Error deleting block $blockId: $error');
    }
  }

  @override
  void updateBlockContent(String id, dynamic content, {
    String? type, 
    double? order, 
    bool immediate = false,
    bool updateLocalOnly = false
  }) {
    // Cancel any existing timer for this block
    final Timer? timer = _saveTimers[id];
    if (timer != null) {
      timer.cancel();
    }
    
    // If the block doesn't exist, exit
    if (!_blocks.containsKey(id)) {
      _logger.warning('Attempted to update non-existent block: $id');
      return;
    }
    
    final Block existingBlock = _blocks[id]!;
    
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
    
    // Always include spans field in content update to preserve formatting
    // If spans aren't in the new content but are in the existing block, preserve them
    if (!contentMap.containsKey('spans') && existingBlock.content is Map) {
      final existingContent = existingBlock.content as Map;
      if (existingContent.containsKey('spans')) {
        contentMap['spans'] = existingContent['spans'];
      }
    }
    
    // Update local block without waiting for server response
    _blocks[id] = existingBlock.copyWith(
      content: contentMap,
      type: type ?? existingBlock.type,
      order: order ?? existingBlock.order
    );
    
    // Track this as a user modification
    _documentBuilder.markBlockAsModified(id);
    
    // Notify listeners for UI responsiveness
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
  Future<void> _saveBlockToBackend(String id, dynamic content, {String? type, double? order}) async {
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
      
      // Update local block with returned data
      _blocks[id] = updatedBlock;
      
      // Clear modification tracking since we've sent the update
      _documentBuilder.clearModificationTracking(id);
      
      _enqueueNotification();
    } catch (error) {
      _logger.error('Error saving block $id', error);
    }
  }

  @override
  void subscribeToVisibleBlocks(String noteId, List<String> visibleBlockIds) {
    // Only subscribe to individual blocks that are visible
    for (final blockId in visibleBlockIds) {
      if (!_webSocketService.isSubscribed('block', id: blockId)) {
        _webSocketService.subscribe('block', id: blockId);
      }
    }
  }

  @override
  bool hasMoreBlocks(String noteId) {
    final state = _paginationState[noteId];
    if (state == null) return true; // If no state, assume we might have more
    
    return state['has_more'] ?? false;
  }

  @override
  Map<String, dynamic> getPaginationInfo(String noteId) {
    return _paginationState[noteId] ?? {
      'page': 1,
      'page_size': 100,
      'total_count': 0,
      'has_more': false
    };
  }

  @override
  void activateNote(String noteId) {
    _activeNoteIds.add(noteId);
    
    // Register note and automatically subscribe
    if (_webSocketService.isConnected) {
      // Subscribe to the note itself
      _webSocketService.subscribe('note', id: noteId);
      
      // Also subscribe to any blocks we already have for this note
      final List<String>? blockIds = _noteBlocksMap[noteId];
      if (blockIds != null) {
        for (final String blockId in blockIds) {
          _webSocketService.subscribe('block', id: blockId);
        }
      }
    }
    
    _logger.debug('Note $noteId activated');
  }

  @override
  void deactivateNote(String noteId) {
    _activeNoteIds.remove(noteId);
    
    // Cancel any pending save timers for blocks in this note
    final blocksForNote = getBlocksForNote(noteId);
    for (final block in blocksForNote) {
      final Timer? timer = _saveTimers[block.id];
      if (timer != null) {
        timer.cancel();
        _saveTimers.remove(block.id);
      }
    }

    // Unsubscribe from resources
    if (_webSocketService.isConnected) {
      _webSocketService.unsubscribe('note', id: noteId);
      
      // Unsubscribe from blocks
      final List<String>? blockIds = _noteBlocksMap[noteId];
      if (blockIds != null) {
        for (final String blockId in blockIds) {
          _webSocketService.unsubscribe('block', id: blockId);
        }
      }
    }
    
    _logger.debug('Note $noteId deactivated');
  }
  
  @override
  void setBlocks(List<Block> blocks) {
    if (blocks.isEmpty) return;
    
    // Update local storage
    for (final block in blocks) {
      _blocks[block.id] = block;
      
      // Update note blocks map
      final noteId = block.noteId;
      _noteBlocksMap[noteId] ??= [];
      if (!_noteBlocksMap[noteId]!.contains(block.id)) {
        _noteBlocksMap[noteId]!.add(block.id);
      }
    }
    
    // Initialize document with blocks
    _documentBuilder.populateDocumentFromBlocks(blocks);
    
    // Set note ID if not already set
    if (noteId == null && blocks.isNotEmpty) {
      noteId = blocks.first.noteId;
    }
    
    notifyListeners();
  }

  @override
  void updateBlocks(List<Block> blocks, {
    bool preserveFocus = false,
    dynamic savedSelection,
    bool markAsModified = true
  }) {
    _logger.info('Updating blocks: received ${blocks.length}');
    
    if (blocks.isEmpty) return;
    
    // Get current selection and focus state if preserving focus
    final currentSelection = preserveFocus ? 
        savedSelection ?? _documentBuilder.composer.selection : null;
    final hasFocus = preserveFocus ? _documentBuilder.focusNode.hasFocus : false;
    
    // Update local storage
    for (final block in blocks) {
      _blocks[block.id] = block;
      
      // Update note blocks map
      final noteId = block.noteId;
      _noteBlocksMap[noteId] ??= [];
      if (!_noteBlocksMap[noteId]!.contains(block.id)) {
        _noteBlocksMap[noteId]!.add(block.id);
      }
    }
    
    // Update document with blocks, preserving focus if needed
    _documentBuilder.populateDocumentFromBlocks(blocks, markAsModified: markAsModified);
    
    // Restore focus if needed
    if (preserveFocus && hasFocus && currentSelection != null) {
      Future.microtask(() {
        // Try to restore selection
        bool restored = _documentBuilder.tryRestoreSelection(currentSelection);
        
        if (!restored) {
          // Find alternative position
          final alternativePosition = _documentBuilder.findBestAlternativePosition();
          if (alternativePosition != null) {
            _documentBuilder.composer.setSelectionWithReason(
              DocumentSelection(
                base: alternativePosition,
                extent: alternativePosition,
              ),
              SelectionReason.contentChange
            );
          }
          
          // Ensure focus is still applied
          _documentBuilder.focusNode.requestFocus();
        }
      });
    }
    
    notifyListeners();
  }

  @override
  void addBlocks(List<Block> blocks) {
    if (blocks.isEmpty) return;
    
    _logger.info('Adding ${blocks.length} blocks to document');
    
    // Filter to only new blocks not already in map
    final newBlocks = blocks.where((block) => !_blocks.containsKey(block.id)).toList();
    
    if (newBlocks.isEmpty) {
      _logger.debug('No new blocks to add, skipping update');
      // IMPORTANT FIX: Update pagination state to indicate no more data
      if (_noteId != null) {
        final currentPagination = _paginationState[_noteId!] ?? {};
        _paginationState[_noteId!] = {
          ...currentPagination,
          'has_more': false
        };
      }
      return;
    }
    
    // Get current selection for preservation
    final currentSelection = _documentBuilder.composer.selection;
    final hasFocus = _documentBuilder.focusNode.hasFocus;
    
    // Add blocks to storage
    for (final block in newBlocks) {
      _blocks[block.id] = block;
      
      // Update note blocks map
      final noteId = block.noteId;
      _noteBlocksMap[noteId] ??= [];
      if (!_noteBlocksMap[noteId]!.contains(block.id)) {
        _noteBlocksMap[noteId]!.add(block.id);
      }
    }
    
    // Sort by order
    newBlocks.sort((a, b) => a.order.compareTo(b.order));
    
    // Add blocks to document
    _updatingDocument = true;
    try {
      for (final block in newBlocks) {
        final nodes = _documentBuilder.createNodesFromBlock(block);
        for (final node in nodes) {
          _documentBuilder.document.add(node);
          _documentBuilder.nodeToBlockMap[node.id] = block.id;
        }
      }
    } finally {
      _updatingDocument = false;
    }
    
    // Restore focus if needed
    if (hasFocus && currentSelection != null) {
      Future.microtask(() {
        _documentBuilder.tryRestoreSelection(currentSelection);
      });
    }
    
    notifyListeners();
  }

  @override
  void updateBlockCache(List<Block> blocks) {
    for (final block in blocks) {
      // Only update if this block belongs to an active note
      if (_noteId == block.noteId || _activeNoteIds.contains(block.noteId)) {
        _blocks[block.id] = block;
        _documentBuilder.registerServerBlock(block);
      }
    }
  }

  @override
  void commitAllContent() {
    _logger.debug('Committing content for all blocks');
    
    // First commit any uncommitted nodes
    _commitUncommittedNodes();
    
    // Then commit content for all current blocks
    for (final nodeId in _documentBuilder.document.map((node) => node.id).toList()) {
      final blockId = _documentBuilder.nodeToBlockMap[nodeId];
      if (blockId != null) {
        _commitBlockContentChange(nodeId);
      }
    }
  }
  
  // Try to create blocks for any uncommitted nodes
  void _commitUncommittedNodes() async {
    if (_documentBuilder.uncommittedNodes.isEmpty) return;
    
    _logger.info('Creating blocks for ${_documentBuilder.uncommittedNodes.length} uncommitted nodes');
    
    // Make a copy of the keys to avoid concurrent modification
    final nodeIds = List.from(_documentBuilder.uncommittedNodes.keys);
    
    for (final nodeId in nodeIds) {
      final node = _documentBuilder.document.getNodeById(nodeId);
      if (node != null) {
        await _createBlockForNode(nodeId, node);
      } else {
        // Node no longer exists, remove from tracking
        _documentBuilder.uncommittedNodes.remove(nodeId);
      }
    }
  }
  
  @override
  void markBlockAsModified(String blockId) {
    _documentBuilder.markBlockAsModified(blockId);
  }

  @override
  Future<void> fetchBlockFromEvent(String blockId) async {
    await fetchBlockById(blockId);
  }

  @override
  void requestFocus() {
    if (!_documentBuilder.focusNode.hasFocus) {
      _logger.debug('Requesting focus for editor');
      _documentBuilder.focusNode.requestFocus();
    }
  }

  @override
  void setFocusToBlock(String blockId) {
    _logger.debug('Setting focus to block: $blockId');
    
    // Find any node that maps to this block
    String? nodeId;
    _documentBuilder.nodeToBlockMap.forEach((nId, bId) {
      if (bId == blockId) {
        nodeId = nId;
      }
    });
    
    if (nodeId != null) {
      // Store for consumption by the UI
      _focusRequestedBlockId = blockId;
      notifyListeners();
    }
  }

  @override
  String? consumeFocusRequest() {
    final String? blockId = _focusRequestedBlockId;
    _focusRequestedBlockId = null; // Clear after consumption
    return blockId;
  }

  @override
  void resetState() {
    _logger.info('Resetting NoteEditorProvider state');
    
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
    _noteId = null;
    
    // Reset document
    _documentBuilder = _documentBuilderFactory();
    
    notifyListeners();
  }

  @override
  void dispose() {
    _logger.info('Disposing NoteEditorProvider');
    
    // Cancel subscriptions
    _resetSubscription?.cancel();
    _connectionSubscription?.cancel();
    
    // Cancel all debounce timers
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    _saveTimers.clear();
    _notificationDebouncer?.cancel();
    
    // Commit any pending changes
    if (_isActive) {
      commitAllContent();
    }
    
    // Remove event listeners
    _webSocketService.removeEventListener('event', 'block.updated');
    _webSocketService.removeEventListener('event', 'block.created');
    _webSocketService.removeEventListener('event', 'block.deleted');
    _webSocketService.removeEventListener('event', 'note.updated');
    
    // Remove document listeners
    _documentBuilder.removeDocumentStructureListener(_documentStructureChangeListener);
    _documentBuilder.removeDocumentContentListener(_documentChangeListener);
    _documentBuilder.focusNode.removeListener(_handleFocusChange);
    
    // Dispose document builder
    _documentBuilder.dispose();
    
    super.dispose();
  }
}
