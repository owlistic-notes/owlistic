import 'dart:async';
import 'package:flutter/material.dart';
import 'package:owlistic/utils/data_converter.dart';
import 'package:super_editor/super_editor.dart' hide Logger;

import 'package:owlistic/services/block_service.dart';
import 'package:owlistic/services/auth_service.dart';
import 'package:owlistic/services/websocket_service.dart';
import 'package:owlistic/services/note_service.dart';
import 'package:owlistic/models/block.dart';
import 'package:owlistic/models/note.dart';
import 'package:owlistic/utils/document_builder.dart';
import 'package:owlistic/utils/attributed_text_utils.dart';
import 'package:owlistic/utils/logger.dart';
import 'package:owlistic/utils/websocket_message_parser.dart';
import 'package:owlistic/viewmodel/note_editor_viewmodel.dart';
import 'package:owlistic/services/app_state_service.dart';

class NoteEditorProvider with ChangeNotifier implements NoteEditorViewModel {
  final Logger _logger = Logger('NoteEditorProvider');
  
  final AttributedTextUtils _attributedTextUtils = AttributedTextUtils();
  
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
  
  // Scroll controller
  ScrollController? _scrollController;
  bool _isLoadingMoreBlocks = false;

  // Active notes tracking
  final Set<String> _activeNoteIds = {};
  
  // Pagination state
  final Map<String, Map<String, dynamic>> _paginationState = {};
  
  // Debouncing mechanisms
  final Map<String, Timer> _saveTimers = {};
  Timer? _notificationDebouncer;
  bool _hasPendingNotification = false;
  
  // Event callbacks
  void Function(String blockId, Map<String, dynamic> content)? _onBlockContentChanged;
  void Function(List<String> blockIds)? _onMultiBlockOperation;
  
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
      notifyListeners();
      
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
      rethrow;
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
    _commitUncommittedNodes();
    
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
      _documentBuilder.removeUncommittedNode(nodeId);
      return;
    }
    
    _logger.info('Node $nodeId was deleted, will delete block $blockId on server');
    
    // Remove from our mappings
    _documentBuilder.removeNodeMapping(nodeId);
    
    // Remove from blocks list if it exists
    _blocks.remove(blockId);
    
    // Remove from note blocks map
    if (_noteId != null && _noteBlocksMap.containsKey(_noteId)) {
      _noteBlocksMap[_noteId!]?.remove(blockId);
    }
    
    // Delete from server
    _blockService.deleteBlock(blockId);
    
    // Notify listeners
    notifyListeners();
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
      String blockType = DocumentBuilder.extractTypeFromNode(node);

      // Extract content from node in the format needed by API
      final extractedData = DocumentBuilder.extractNodeContent(
        node,
        originalBlock: _blocks[_documentBuilder.nodeToBlockMap[node.id]]
      );

      if (blockType.startsWith('header')) {
        blockType = 'header';
        final levelStr = blockType.substring(6);
        extractedData['metadata']['level'] = DataConverter.parseIntSafely(levelStr);
      }

      // Calculate a fractional order value using the document builder
      double order = await _documentBuilder.calculateOrderForNewNode(nodeId, blocks);
      
      _logger.debug('Creating block of type $blockType with fractional order $order');
      
      // Create block through BlockService
      final block = await _blockService.createBlock(
        noteId!, 
        extractedData,
        blockType,
        order
      );
      
      // Update our mappings
      _documentBuilder.linkNodeToBlock(nodeId, block.id);
      _blocks[block.id] = block;
      
      // Add to note blocks map
      _noteBlocksMap[noteId!] ??= [];
      if (!_noteBlocksMap[noteId!]!.contains(block.id)) {
        _noteBlocksMap[noteId!]!.add(block.id);
      }
      
      // Remove from uncommitted nodes
      _documentBuilder.removeUncommittedNode(nodeId);
      
      // Subscribe to this block
      _webSocketService.subscribe('block', id: block.id);
      
      // Notify listeners
      notifyListeners();
      
      _logger.info('Successfully created block ${block.id} for node $nodeId');
    } catch (e) {
      _logger.error('Failed to create block for node $nodeId: $e');
      // Remove from uncommitted nodes to prevent infinite retry loops
      _documentBuilder.removeUncommittedNode(nodeId);
    }
  }
  
  // DocumentChangeListener implementation for content changes
  void _documentChangeListener(dynamic _) {
    if (_updatingDocument) return;
    
    // Check if this change is a DocumentChangeLog which might contain TaskNode changes
    if (_ is DocumentChangeLog) {
      DocumentChangeLog changeLog = _;
      
      // Check if this change includes a TaskNode's isComplete property change
      bool hasTaskStateChange = false;
      String? taskNodeId;
      bool? newCompletionState;
      
      for (final change in changeLog.changes) {
        if (change is NodeChangeEvent) {
          final node = _documentBuilder.document.getNodeById(change.nodeId);
          if (node is TaskNode) {
            taskNodeId = change.nodeId;
            newCompletionState = node.isComplete;
            hasTaskStateChange = true;
            break;
          }
        }
      }
      
      // If a task state changed, handle it immediately
      if (hasTaskStateChange && taskNodeId != null) {
        _handleTaskNodeStateChange(taskNodeId, newCompletionState!);
        return;
      }
    }
    
    // Regular change handling for typing/editing
    _handleDocumentChange();
  }

  // Handle task completion state change
  void _handleTaskNodeStateChange(String nodeId, bool isComplete) {
    // Find the block ID for this node
    final blockId = _documentBuilder.nodeToBlockMap[nodeId];
    if (blockId == null) return;
    
    // Get the block to check against
    final block = getBlock(blockId);
    if (block == null || block.type != 'task') return;
    
    // Compare with current state to see if it actually changed
    final bool wasComplete = block.metadata != null && 
                            block.metadata!['is_completed'] == true;
    
    if (wasComplete != isComplete) {
      _logger.info('Task completion changed: nodeId=$nodeId, blockId=$blockId, isComplete=$isComplete');
      
      // Content ONLY contains text
      final content = {'text': block.getTextContent()};
      
      // Metadata contains everything else
      final metadata = Map<String, dynamic>.from(block.metadata ?? {});
      metadata['_sync_source'] = 'block';
      metadata['is_completed'] = isComplete;
      metadata['block_id'] = blockId;
      
      // Create properly structured payload
      final payload = {
        'content': content,
        'metadata': metadata
      };
      
      // Send immediate update to server with standardized format
      updateBlock(blockId, payload);
    }
  }

  // Track which block is being edited and schedule updates
  void _handleDocumentChange() {
    // Get the node that's currently being edited
    final selection = _documentBuilder.composer.selection;
    if (selection == null) return;
    
    // Get node ID from selection
    final nodeId = selection.extent.nodeId;
    
    // Find the block ID for this node
    final blockId = _documentBuilder.nodeToBlockMap[nodeId];
    if (blockId == null) return;
    
    // Set the current editing block
    _currentEditingBlockId = blockId;
    _lastEdit = DateTime.now();
    
    // Mark the block as modified by the user
    _documentBuilder.markBlockAsModified(blockId);
    _documentBuilder.markNodeAsUncommitted(nodeId);
  }

  // Handle focus change
  void _handleFocusChange() {
    if (!_documentBuilder.focusNode.hasFocus) {
      // Commit any pending changes
      _commitUncommittedNodes();
    }
  }

  // Commit changes for a specific node
  void _commitNodeChange(String nodeId) {
    // Find block ID for this node
    final blockId = _documentBuilder.nodeToBlockMap[nodeId];
    if (blockId == null) return;
    
    // Find node in document
    final node = _documentBuilder.document.getNodeById(nodeId);
    if (node == null) return;
    
    // Find the block to extract content against
    final block = getBlock(blockId);
    if (block == null) return;
    
    // Extract node type for determining block.type
    String blockType = DocumentBuilder.extractTypeFromNode(node);
    
    // Extract content from node with proper formatting
    final extractedData = DocumentBuilder.extractContentFromNode(node, blockId, block);

    if (blockType.startsWith('header')) {
      blockType = 'header';
      final levelStr = blockType.substring(6);
      extractedData['metadata']['level'] = DataConverter.parseIntSafely(levelStr);
    }

    // Send content update with formats included
    updateBlock(blockId, extractedData, type: blockType);
  }
  
  // WebSocket event handlers
  void _handleBlockUpdate(Map<String, dynamic> message) {
    try {
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? blockId = WebSocketModelExtractor.extractBlockId(parsedMessage);
      final String? eventNoteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      // Quick exit if we don't have necessary information
      if (blockId == null) return;
      
      _logger.info('Received block update event for blockId=$blockId, noteId=$eventNoteId');
      
      // Check if we should care about this block
      bool shouldUpdate = _blocks.containsKey(blockId) || 
                         (_noteId == eventNoteId) ||
                         (_activeNoteIds.contains(eventNoteId ?? ''));
      
      if (shouldUpdate) {
        fetchBlockById(blockId).then((block) {
          if (block != null) {
            _updateDocumentWithBlock(block);
            notifyListeners();
          }
        });
      }
    } catch (e) {
      _logger.error('Error handling block update: $e');
    }
  }
  
  void _handleBlockCreate(Map<String, dynamic> message) {
    try {
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? blockId = WebSocketModelExtractor.extractBlockId(parsedMessage);
      final String? eventNoteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      if (blockId != null && eventNoteId != null && 
          (_noteId == eventNoteId || _activeNoteIds.contains(eventNoteId))) {
        fetchBlockById(blockId).then((block) {
          if (block != null) {
            _addBlockToDocument(block);
            notifyListeners();
          }
        });
      }
    } catch (e) {
      _logger.error('Error handling block create', e);
    }
  }

  void _handleBlockDelete(Map<String, dynamic> message) {
    try {
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? blockId = WebSocketModelExtractor.extractBlockId(parsedMessage);
      
      if (blockId != null && _blocks.containsKey(blockId)) {
        // Keep a reference to the block's note ID
        final noteId = _blocks[blockId]?.noteId;
        
        // Remove from blocks map
        _blocks.remove(blockId);
        
        // Remove from note blocks map if we have the note ID
        if (noteId != null && _noteBlocksMap.containsKey(noteId)) {
          _noteBlocksMap[noteId]?.remove(blockId);
        }
        
        // Remove the node from document
        _documentBuilder.deleteBlockNode(blockId);
        
        // Unsubscribe from this block
        _webSocketService.unsubscribe('block', id: blockId);
        
        // Notify UI
        notifyListeners();
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
    // Get current cache state for this block
    final bool blockExists = _blocks.containsKey(block.id);
    bool nodeExists = false;
    
    // Check if a node for this block already exists
    _documentBuilder.nodeToBlockMap.forEach((nodeId, blockId) {
      if (blockId == block.id) {
        nodeExists = true;
      }
    });
    
    if (nodeExists) {
      // Update existing node - simple case
      _documentBuilder.updateBlockNode(block);
    } else {
      // This is a new block, find where to insert it
      final insertIndex = _documentBuilder.findInsertIndexForBlock(block, blocks);
      _documentBuilder.insertBlockNode(block, index: insertIndex);
    }
    
    // Update the block in our storage
    _blocks[block.id] = block;
    
    // Subscribe to this block if it's new
    if (!blockExists) {
      _webSocketService.subscribe('block', id: block.id);
    }
  }
  
  // Add a block to the document
  void _addBlockToDocument(Block block) {
    // Only add if this block belongs to the current note
    if (_noteId != block.noteId) return;
    
    // Update local storage
    _blocks[block.id] = block;
    
    // Update note blocks map
    _noteBlocksMap[block.noteId] ??= [];
    if (!_noteBlocksMap[block.noteId]!.contains(block.id)) {
      _noteBlocksMap[block.noteId]!.add(block.id);
    }

    _updateDocumentWithBlock(block);
  }

  // Implementation of NoteEditorViewModel methods
  
  @override
  Future<List<Block>> fetchBlocksForNote(String noteId, {
    int page = 1,
    int pageSize = 100,
    bool append = false,
    bool refresh = false
  }) async {
    if (!append) {
      _isLoading = true;
      notifyListeners(); // Notify immediately about loading state
    }
    
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
        _blocks[block.id] = block;
        if (!_noteBlocksMap[noteId]!.contains(block.id)) {
          _noteBlocksMap[noteId]!.add(block.id);
          newBlockCount++;
        }
      }
      
      // Update pagination state
      final bool hasMore = blocksResult.length >= pageSize;
      _paginationState[noteId] = {
        'page': page,
        'page_size': pageSize,
        'has_more': hasMore
      };
      
      _logger.debug('Pagination state updated for $noteId: hasMore=$hasMore, newBlocks=$newBlockCount, results=${blocksResult.length}');
      
      // Update document
      if (_noteId == noteId && !append) {
        setBlocks(blocksResult);
      } else if (_noteId == noteId && append) {
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
      final Block block = await _blockService.getBlock(blockId);
      
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
      notifyListeners();
      
      return block;
    } catch (error) {
      _logger.error('Error fetching block $blockId', error);
      return null;
    }
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
          _documentBuilder.removeNodeMapping(nodeId);
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
  void updateBlock(String id, Map<String, dynamic> content, {
    String? type, 
    double? order,
  }) {
    // If the block doesn't exist, exit
    if (!_blocks.containsKey(id)) {
      _logger.warning('Attempted to update non-existent block: $id');
      return;
    }
    
    final Block existingBlock = _blocks[id]!;
    
    // Process content to proper format
    Map<String, dynamic> contentMap = Map<String, dynamic>.from(content['content']);
    Map<String, dynamic>? metadataMap = Map<String, dynamic>.from(content['metadata']);

    // Update local block without waiting for server response
    _blocks[id] = existingBlock.copyWith(
      content: contentMap,
      metadata: metadataMap,
      type: type ?? existingBlock.type,
      order: order ?? existingBlock.order,
    );
    
    // Track this as a user modification
    _documentBuilder.markBlockAsModified(id);
    
    // Notify listeners for UI responsiveness
    notifyListeners();
    _updateBlock(id, contentMap, metadata: metadataMap, type: type, order: order);
  }

  Future<void> _updateBlock(String id,
    Map<String, dynamic> content, {
    Map<String, dynamic>? metadata,
    String? type, 
    double? order
  }) async {
    if (!_blocks.containsKey(id)) return;
    
    try {
      _logger.debug('Saving block $id to server');
      
      // FIXED: Create properly structured payload
      final payload = <String, dynamic>{};
      
      // Set content in payload
      payload['content'] = content;
      
      // Add block type if specified
      if (type != null) {
        payload['type'] = type;
      }
      
      // Add order if specified
      if (order != null) {
        payload['order'] = order;
      }
      
      // Setup metadata
      Map<String, dynamic> metadataMap = metadata ?? {};
      metadataMap['_sync_source'] = 'block';
      metadataMap['block_id'] = id;
      
      // Add metadata to payload
      payload['metadata'] = metadataMap;
      
      _logger.debug('Sending payload to server: $payload');
      
      // Update via BlockService
      final updatedBlock = await _blockService.updateBlock(id, payload);
      
      // Update local block with returned data
      _blocks[id] = updatedBlock;
      
      // Clear modification tracking since we've sent the update
      _documentBuilder.clearModificationTracking(id);
      
      notifyListeners();
    } catch (error) {
      _logger.error('Error saving block $id', error);
    }
  }

  @override
  void initScrollListener(ScrollController scrollController) {
    _logger.debug('Initializing scroll listener for pagination');
    
    // Remove existing listener if any
    if (_scrollController != null) {
      _scrollController!.removeListener(_handleScroll);
    }
    
    // Store reference to the controller
    _scrollController = scrollController;
    
    // Add scroll listener
    _scrollController!.addListener(_handleScroll);
    
    _logger.debug('Scroll listener initialized successfully');
  }
  
  // Improved scroll handler with better logging and scroll position detection
  void _handleScroll() {
    if (_scrollController == null || !_scrollController!.hasClients) return;
    if (_noteId == null) return;
    if (_isLoading || _isLoadingMoreBlocks) return;
    
    // Calculate scroll position
    final maxScroll = _scrollController!.position.maxScrollExtent;
    final currentScroll = _scrollController!.position.pixels;
    const threshold = 500.0; // Load more when within 500px of bottom
    
    if (maxScroll - currentScroll <= threshold) {
      // Check if we have more blocks to load
      if (hasMoreBlocks(_noteId!)) {
        _logger.info('Scroll threshold reached at ${currentScroll.toStringAsFixed(1)}/${maxScroll.toStringAsFixed(1)}, loading more blocks');
        _loadMoreBlocks();
      } else {
        _logger.debug('Reached end of content, no more blocks to load');
      }
    }
  }
  
  // Simplified and improved _loadMoreBlocks method
  void _loadMoreBlocks() async {
    if (_noteId == null) return;
    if (_isLoadingMoreBlocks) return; // Prevent multiple concurrent loads
    
    try {
      _isLoadingMoreBlocks = true;
      
      // Get current pagination info
      final paginationInfo = _paginationState[_noteId!] ?? {'page': 1, 'page_size': 100};
      final nextPage = (paginationInfo['page'] ?? 1) + 1;
      final pageSize = paginationInfo['page_size'] ?? 30; // Use smaller page size for smoother loading
      
      _logger.info('Loading more blocks for note $_noteId (page $nextPage)');
      
      // Fetch the next page of blocks with append=true
      final newBlocks = await _blockService.fetchBlocksForNote(_noteId!, 
          queryParams: {
            'note_id': _noteId,
            'page': nextPage,
            'page_size': pageSize,
          });
      
      // Update pagination state based on results
      final hasMore = newBlocks.length >= pageSize;
      _paginationState[_noteId!] = {
        'page': nextPage,
        'page_size': pageSize,
        'has_more': hasMore
      };
      
      // Add the new blocks to the document
      if (newBlocks.isNotEmpty) {
        // Process and add blocks to the document
        final blocksToAdd = newBlocks.where((block) => !_blocks.containsKey(block.id)).toList();
        
        _logger.debug('Fetched ${newBlocks.length} blocks, adding ${blocksToAdd.length} new blocks (page $nextPage)');
        
        // If we have new blocks, add them to the document
        if (blocksToAdd.isNotEmpty) {
          addBlocks(blocksToAdd);
        } else if (newBlocks.isEmpty || blocksToAdd.isEmpty) {
          // If we didn't get any new blocks, mark that we have no more blocks
          _paginationState[_noteId!]!['has_more'] = false;
          _logger.debug('No new blocks received, marking pagination complete for $_noteId');
        }
      } else {
        // No blocks returned, mark pagination as complete
        _paginationState[_noteId!]!['has_more'] = false;
        _logger.debug('Empty response, marking pagination complete for $_noteId');
      }
      
      notifyListeners(); // Notify listeners about the update
      
    } catch (e) {
      _logger.error('Error loading more blocks for note $_noteId: $e');
      _errorMessage = 'Failed to load more content: $e';
    } finally {
      _isLoadingMoreBlocks = false;
    }
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
      _commitUncommittedNodes();
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
  
    // Remove scroll listener
    if (_scrollController != null) {
      _scrollController!.removeListener(_handleScroll);
    }
    
    // Dispose document builder
    _documentBuilder.dispose();
    
    super.dispose();
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
    
    // For initial loading, we'll rebuild the document
    _documentBuilder.populateDocumentFromBlocks(blocks);
    
    // Set note ID if not already set
    if (noteId == null && blocks.isNotEmpty) {
      noteId = blocks.first.noteId;
    }
    
    notifyListeners();
  }

  @override
  void addBlocks(List<Block> blocks) {
    if (blocks.isEmpty) return;
    
    // Filter to only new blocks
    final newBlocks = blocks.where((block) => !_blocks.containsKey(block.id)).toList();
    
    if (newBlocks.isEmpty) {
      // Update pagination state to indicate no more data
      if (_noteId != null) {
        final currentPagination = _paginationState[_noteId!] ?? {};
        _paginationState[_noteId!] = {
          ...currentPagination,
          'has_more': false
        };
      }
      return;
    }
    
    // Remember if editor has focus and current selection
    final hasFocus = _documentBuilder.focusNode.hasFocus;
    final currentSelection = _documentBuilder.composer.selection;
    
    // Update storage
    for (final block in newBlocks) {
      _blocks[block.id] = block;
      
      // Update note blocks map
      final noteId = block.noteId;
      _noteBlocksMap[noteId] ??= [];
      if (!_noteBlocksMap[noteId]!.contains(block.id)) {
        _noteBlocksMap[noteId]!.add(block.id);
      }
    }
    
    // Sort and add to document
    newBlocks.sort((a, b) => a.order.compareTo(b.order));
    for (final block in newBlocks) {
      final insertIndex = _documentBuilder.findInsertIndexForBlock(block, blocks);
      _documentBuilder.insertBlockNode(block, index: insertIndex);
    }
    
    // Restore focus if needed - simpler approach
    if (hasFocus && currentSelection != null) {
      Future.microtask(() => _documentBuilder.tryRestoreSelection(currentSelection));
    }
    
    notifyListeners();
  }

  @override
  void commitAllNodes() {
    _logger.debug('Committing content for all blocks');
        // First commit any uncommitted nodes
    _commitUncommittedNodes();
    
    // Then commit content for all current blocks
    for (final nodeId in _documentBuilder.document.map((node) => node.id).toList()) {
      final blockId = _documentBuilder.nodeToBlockMap[nodeId];
      if (blockId != null) {
        _commitNodeChange(nodeId);
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
      _commitNodeChange(nodeId);
    }
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
}
