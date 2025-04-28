import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart' hide Logger;
import '../models/block.dart';
import '../utils/logger.dart';
import '../services/block_service.dart';
import '../utils/document_builder.dart';
import '../viewmodel/rich_text_editor_viewmodel.dart';

/// Provider for managing the state of a full-page rich text editor that combines multiple blocks
class RichTextEditorProvider with ChangeNotifier implements RichTextEditorViewModel {
  final Logger _logger = Logger('RichTextEditorProvider');
  String? _errorMessage;
  bool _isLoading = false;
  bool _isInitialized = false;
  bool _isActive = false;
  String? _noteId;

  // Document mapper handles all SuperEditor document operations
  late DocumentBuilder _documentBuilder;
  // Getter for document builder
  @override
  DocumentBuilder get documentBuilder => _documentBuilder;
  
  // Callbacks for various events
  void Function(String blockId, dynamic content)? _onBlockContentChanged;
  void Function(List<String> blockIds)? _onMultiBlockOperation;
  void Function(String blockId)? _onBlockDeleted;
  void Function()? _onFocusLost;
  
  // Add current note ID to track which note blocks belong to
  @override
  String? get noteId => _noteId;
  
  @override
  set noteId(String? value) {
    _noteId = value;
    notifyListeners();
  }
  
  // Use BlockService directly instead of BlockProvider
  final BlockService _blockService;
  
  // Function to create document builder instances
  final DocumentBuilder Function() _documentBuilderFactory;

  // Get the mapping between document node IDs and block IDs
  getNodeToBlockMapping() {
    return _documentBuilder.nodeToBlockMap;
  }
  
  // The blocks used to create the document
  List<Block> _blocks = [];
  
  // Track backspace/delete keys for merging blocks
  bool _isBackspacePressed = false;
  bool _isDeletePressed = false;
  
  // Track multi-block selection state
  DocumentSelection? _previousSelection;
  Set<String> _affectedBlockIds = {};
  
  // Keep track of original blocks at initialization for reconciliation
  final List<Block> _originalBlocks = [];
  
  // Content update debouncer
  DateTime _lastEdit = DateTime.now();
  String? _currentEditingBlockId;
  
  // Flag to prevent recursive document updates
  bool _updatingDocument = false;
  
  // Cache of server blocks for timestamp comparison
  final Map<String, Block> _serverBlockCache = {};
  
  // Constructor with service-based dependency injection
  RichTextEditorProvider({
    required BlockService blockService,
    required DocumentBuilder Function() documentBuilderFactory,
    String? noteId,
    List<Block>? initialBlocks,
    void Function(String blockId, dynamic content)? onBlockContentChanged,
    void Function(List<String> blockIds)? onMultiBlockOperation,
    void Function(String blockId)? onBlockDeleted,
    void Function()? onFocusLost,
  }) : _blockService = blockService,
       _documentBuilderFactory = documentBuilderFactory,
       _noteId = noteId {
    
    _documentBuilder = _documentBuilderFactory();
    _onBlockContentChanged = onBlockContentChanged;
    _onMultiBlockOperation = onMultiBlockOperation;
    _onBlockDeleted = onBlockDeleted;
    _onFocusLost = onFocusLost;
    
    if (initialBlocks != null) {
      setBlocks(initialBlocks);
    }
    
    _isInitialized = true;
  }
  
  // Method to set blocks and initialize properly
  @override
  void setBlocks(List<Block> blocks) {
    if (blocks.isEmpty) return;
    
    _blocks = List.from(blocks);
    _originalBlocks.clear();
    _originalBlocks.addAll(blocks);
    
    // Initialize server block cache
    _serverBlockCache.clear();
    for (final block in blocks) {
      _serverBlockCache[block.id] = block;
    }
    
    // Set note ID if not already set
    if (noteId == null && blocks.isNotEmpty) {
      noteId = blocks.first.noteId;
    }
    
    // Initialize document if we have blocks
    if (!_isActive) {
      _initialize();
    } else {
      // Update existing document
      _documentBuilder.populateDocumentFromBlocks(_blocks);
    }
  }
  
  // Update block cache manually without depending on BlockProvider
  @override
  void updateBlockCache(List<Block> blocks) {
    if (noteId == null) return;
    
    // Filter blocks for current note
    final noteBlocks = blocks.where((block) => block.noteId == noteId).toList();
    
    // Update server cache with these blocks
    for (final block in noteBlocks) {
      _serverBlockCache[block.id] = block;
      registerServerBlock(block);
    }
  }
  
  // Register a server block in the document builder
  void registerServerBlock(Block block) {
    _documentBuilder.registerServerBlock(block);
  }
  
  // Convenience getters that access document mapper properties
  MutableDocument get document => _documentBuilder.document;
  MutableDocumentComposer get composer => _documentBuilder.composer;
  Editor get editor => _documentBuilder.editor;
  
  @override
  FocusNode get focusNode => _documentBuilder.focusNode;
  
  @override
  List<Block> get blocks => List.unmodifiable(_blocks);
  
  // Standardized activate/deactivate methods
  @override
  void activate() {
    _isActive = true;
    _logger.info('RichTextEditorProvider activated');
    
    // Register document event to capture split paragraph events
    _documentBuilder.addDocumentStructureListener(_documentStructureChangeListener);
  }

  @override
  void deactivate() {
    _isActive = false;
    _logger.info('RichTextEditorProvider deactivated');
    
    // Commit all content before deactivating
    commitAllContent();
    
    // Remove document structure listener
    _documentBuilder.removeDocumentStructureListener(_documentStructureChangeListener);
  }
  
  // Add resetState for consistency
  @override
  void resetState() {
    _logger.info('Resetting RichTextEditorProvider state');
    // Clear blocks
    _blocks.clear();
    _originalBlocks.clear();
    _serverBlockCache.clear();
    _isActive = false;
    _errorMessage = null;
    notifyListeners();
  }
  
  void _initialize() {
    // Create document mapper
    _documentBuilder = DocumentBuilder();
    
    // Add focus change listener
    _documentBuilder.focusNode.addListener(_handleFocusChange);
    
    // Listen for document content changes
    _documentBuilder.addDocumentContentListener(_documentChangeListener);
    
    // Add blocks to document
    _documentBuilder.populateDocumentFromBlocks(_blocks);
    
    _logger.info('Rich text editor initialized with ${_blocks.length} blocks');
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
    _blocks.removeWhere((block) => block.id == blockId);
    
    // Remove from server cache
    _serverBlockCache.remove(blockId);
    
    // Call the deletion handler to delete on server
    if (_onBlockDeleted != null) {
      _onBlockDeleted!(blockId);
    } else {
      // If no handler, try to delete directly
      _blockService.deleteBlock(blockId);
    }
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
      
      // Extract content and metadata from node
      final extractedData = _extractNodeContentForApi(node);
      final content = extractedData['content'] as Map<String, dynamic>;
      final metadata = extractedData['metadata'] as Map<String, dynamic>?;
      
      // Calculate a fractional order value using the document builder
      double order = await _documentBuilder.calculateOrderForNewNode(nodeId, _blocks);
      
      _logger.debug('Creating block of type $blockType with fractional order $order');
      
      // Create request body with content and metadata
      final Map<String, dynamic> requestBody = {
        'note_id': noteId!,
        'content': content,
        'type': blockType,
        'order': order,
      };
      
      // Add metadata if available
      if (metadata != null && metadata.isNotEmpty) {
        requestBody['metadata'] = metadata;
      }
      
      // Create block through BlockService
      final block = await _blockService.createBlock(
        noteId!, 
        content,
        blockType,
        order
      );
      
      // Update our mappings
      _documentBuilder.nodeToBlockMap[nodeId] = block.id;
      _blocks.add(block);
      
      // Add to server cache
      _serverBlockCache[block.id] = block;
      
      // Remove from uncommitted nodes
      _documentBuilder.uncommittedNodes.remove(nodeId);
      
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
  
  // Try to create blocks for any uncommitted nodes before losing focus
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
  
  // Track which block is being edited and schedule updates
  void _handleDocumentChange() {
    // Get the node that's currently being edited
    final selection = _documentBuilder.composer.selection;
    if (selection == null) return;
    
    // Check if we just completed a multi-block operation
    if (_affectedBlockIds.length > 1) {
      _logger.info('Processing multi-block operation affecting ${_affectedBlockIds.length} blocks');
      
      // Notify about multi-block operation
      _onMultiBlockOperation?.call(_affectedBlockIds.toList());
      
      // Clear affected blocks after handling
      _affectedBlockIds.clear();
      return;
    }
    
    // Get node ID from selection
    final nodeId = selection.extent.nodeId;
    if (nodeId == null) return;
    
    // Find the block ID for this node
    final blockId = _documentBuilder.nodeToBlockMap[nodeId];
    if (blockId == null) return;
    
    // Set the current editing block
    _currentEditingBlockId = blockId;
    _lastEdit = DateTime.now();
    
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
    
    // Find the original block to preserve metadata
    final originalBlock = _blocks.firstWhere((b) => b.id == blockId, 
        orElse: () => _serverBlockCache[blockId] ?? _originalBlocks.firstWhere(
          (b) => b.id == blockId, 
          orElse: () => Block(
            id: blockId,
            noteId: noteId!,
            type: 'text',
            content: {'text': ''},
            order: 0
          )
        )
    );
    
    // Extract content and metadata based on node type
    final extractedData = _extractNodeContentForApi(node);
    final updatedContent = extractedData['content'] as Map<String, dynamic>;
    final updatedMetadata = extractedData['metadata'] as Map<String, dynamic>?;
    
    // Merge with existing metadata if available
    Map<String, dynamic>? combinedMetadata;
    if (originalBlock.metadata != null || updatedMetadata != null) {
      combinedMetadata = {};
      if (originalBlock.metadata != null) {
        combinedMetadata.addAll(originalBlock.metadata!);
      }
      if (updatedMetadata != null) {
        combinedMetadata.addAll(updatedMetadata);
      }
    }
    
    // Check if this content should be sent to the server (timestamp-based)
    final serverBlock = _serverBlockCache[blockId];
    bool shouldUpdate = serverBlock == null; // Always update if we don't have server version
    
    if (!shouldUpdate && serverBlock != null) {
      shouldUpdate = _documentBuilder.shouldSendBlockUpdate(blockId, serverBlock);
    }
    
    // Also check if content has actually changed compared to the original
    if (shouldUpdate && serverBlock != null) {
      shouldUpdate = _documentBuilder.hasNodeContentChanged(node, blockId, serverBlock);
    }
    
    if (shouldUpdate) {
      // Send content update
      _logger.debug('Sending block content update for $blockId');
      
      // Create update request with both content and metadata
      final updateData = {
        'content': updatedContent,
      };
      
      // Only include metadata if it has values
      if (combinedMetadata != null && combinedMetadata.isNotEmpty) {
        updateData['metadata'] = combinedMetadata;
      }
      
      _onBlockContentChanged?.call(blockId, updateData);
      
      // After successful update, update server cache with estimated new version
      final updatedBlock = originalBlock.copyWith(
        content: updatedContent,
        metadata: combinedMetadata,
        updatedAt: DateTime.now()
      );
      _serverBlockCache[blockId] = updatedBlock;
      
      // Clear modification tracking since we've sent the update
      _documentBuilder.clearModificationTracking(blockId);
    } else {
      _logger.debug('Skipping update for $blockId - content not changed or server has newer version');
    }
    
    _currentEditingBlockId = null;
  }
  
  // Delete a block
  @override
  void deleteBlock(String blockId) {
    _logger.info('Deleting block: $blockId');
    
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
    
    // Remove from blocks list
    _blocks.removeWhere((block) => block.id == blockId);
    
    // Remove from server cache
    _serverBlockCache.remove(blockId);
    
    // Notify callback
    _onBlockDeleted?.call(blockId);
    
    // Notify listeners
    notifyListeners();
  }
  
  // Enhanced focus change handling
  void _handleFocusChange() {
    if (!_documentBuilder.focusNode.hasFocus) {
      // Try to commit any uncommitted nodes first
      _commitUncommittedNodes();
      
      // Commit any pending changes
      if (_currentEditingBlockId != null) {
        final nodeIds = _documentBuilder.document.map((node) => node.id).toList();
        for (final nodeId in nodeIds) {
          if (_documentBuilder.nodeToBlockMap[nodeId] == _currentEditingBlockId) {
            _commitBlockContentChange(nodeId);
            break;
          }
        }
      }
      
      // Commit all content changes for all blocks before notifying about focus loss
      for (final blockId in getCurrentBlockIds()) {
        _commitContentForBlock(blockId);
      }
      
      _onFocusLost?.call();
    }
    notifyListeners();
  }
  
  // Get all current block IDs
  List<String> getCurrentBlockIds() {
    return _blocks.map((b) => b.id).toList();
  }
  
  // Commit content for a specific block
  void _commitContentForBlock(String blockId) {
    // Find the node for this block
    String? nodeId;
    for (final entry in _documentBuilder.nodeToBlockMap.entries) {
      if (entry.value == blockId) {
        nodeId = entry.key;
        break;
      }
    }
    
    if (nodeId != null) {
      _commitBlockContentChange(nodeId);
    }
  }

  // Update blocks and refresh the document
  @override
  void updateBlocks(List<Block> blocks, {
    bool preserveFocus = false,
    dynamic savedSelection,
    bool markAsModified = true
  }) {
    _logger.info('Updating blocks: received ${blocks.length}, current ${_blocks.length}');
    
    if (_blocks.isEmpty && blocks.isNotEmpty) {
      // Initial load - just populate the document
      _blocks = List.from(blocks);
      
      // Update server cache
      for (final block in blocks) {
        _serverBlockCache[block.id] = block;
      }
      
      _documentBuilder.populateDocumentFromBlocks(_blocks);
      notifyListeners();
      return;
    }
    
    // Update server cache with latest blocks from server
    for (final block in blocks) {
      _serverBlockCache[block.id] = block;
      
      // Register this block in the document builder
      registerServerBlock(block);
    }
    
    // Get current selection and focus state if preserving focus
    final currentSelection = preserveFocus ? savedSelection ?? composer.selection : null;
    final hasFocus = preserveFocus ? focusNode.hasFocus : false;
    
    // Create maps for efficient lookups
    final Map<String, Block> existingBlocksMap = {
      for (var block in _blocks) block.id: block
    };
    
    final Map<String, Block> newBlocksMap = {
      for (var block in blocks) block.id: block
    };
    
    // Determine what kind of update is needed
    bool hasStructuralChanges = false;
    bool onlyAddedAtEnd = true;
    
    // Check first for additions/removals
    if (existingBlocksMap.length != newBlocksMap.length) {
      hasStructuralChanges = true;
      
      // If we're only adding blocks, check if they're all at the end
      if (existingBlocksMap.length < newBlocksMap.length) {
        // Are all existing blocks still present?
        onlyAddedAtEnd = existingBlocksMap.keys.every((id) => newBlocksMap.containsKey(id));
        
        if (onlyAddedAtEnd) {
          // Find the highest order of existing blocks
          final highestExistingOrder = _blocks.isEmpty ? -1 : 
              _blocks.map((b) => b.order).reduce((a, b) => a > b ? a : b);
              
          // Check if all new blocks have higher order
          for (final blockId in newBlocksMap.keys) {
            if (!existingBlocksMap.containsKey(blockId) && 
                newBlocksMap[blockId]!.order <= highestExistingOrder) {
              onlyAddedAtEnd = false;
              break;
            }
          }
        }
      } else {
        // We're removing blocks, so not just adding at end
        onlyAddedAtEnd = false;
      }
    }
    
    // CASE 1: Blocks only added at the end - we can append without disrupting focus
    if (hasStructuralChanges && onlyAddedAtEnd) {
      _logger.info('Only adding blocks at end, performing targeted update');
      
      // Get blocks to add (in new blocks but not in existing blocks)
      final blocksToAdd = blocks
          .where((b) => !existingBlocksMap.containsKey(b.id))
          .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
      
      // Add the blocks to our list
      _blocks = List.from(_blocks)..addAll(blocksToAdd);
      
      // Create nodes for these blocks and add them to the document
      for (final block in blocksToAdd) {
        final nodes = _documentBuilder.createNodesFromBlock(block);
        for (final node in nodes) {
          document.add(node);
          _documentBuilder.nodeToBlockMap[node.id] = block.id;
        }
      }
      
      // Restore focus if needed - use contentChange reason
      if (preserveFocus && currentSelection != null) {
        Future.microtask(() {
          restoreFocus(currentSelection);
        });
      }
      
      notifyListeners();
      return;
    }
    
    // CASE 2: More complex changes - need to rebuild document but preserve focus
    if (hasStructuralChanges) {
      _logger.info('Structural changes detected, rebuilding document with focus preservation');
      _blocks = List.from(blocks);
      
      // Make a safe copy of selection to prevent issues during document rebuilding
      final safeSelection = _documentBuilder.createSafeSelectionCopy(currentSelection);
      
      // Use specialized document population with fail-safe focus restoration
      _documentBuilder.populateDocumentFromBlocks(_blocks, markAsModified: markAsModified);
      
      // Restore focus with correct reason and fail-safe mechanisms
      if (preserveFocus && hasFocus) {
        Future.microtask(() {
          // Try to restore selection with better error handling
          bool restored = _documentBuilder.tryRestoreSelection(safeSelection);
          
          if (!restored && hasFocus) {
            // If restoration failed, try to find a reasonable alternative position
            final alternativePosition = _documentBuilder.findBestAlternativePosition();
            if (alternativePosition != null) {
              // Use setSelectionWithReason instead of direct assignment
              composer.setSelectionWithReason(
                DocumentSelection(
                  base: alternativePosition,
                  extent: alternativePosition,
                ),
                SelectionReason.contentChange
              );
            }
            
            // Ensure focus is still applied
            focusNode.requestFocus();
          }
        });
      }
      
      notifyListeners();
      return;
    }
    
    // CASE 3: No structural changes, just content updates
    _logger.debug('No structural changes, updating blocks without document rebuild');
    _blocks = List.from(blocks);
    notifyListeners();
  }

  // Restore focus to a previous position - improved with better error handling
  void restoreFocus(DocumentSelection selection) {
    try {
      // Use the safer document builder method to restore focus
      bool restored = _documentBuilder.tryRestoreSelection(selection);
      
      if (!restored) {
        // Use fallback mechanism for position restoration
        final alternativePosition = _documentBuilder.findBestAlternativePosition();
        if (alternativePosition != null) {
          // Use setSelectionWithReason instead of direct assignment
          composer.setSelectionWithReason(
            DocumentSelection(
              base: alternativePosition,
              extent: alternativePosition,
            ),
            SelectionReason.contentChange
          );
        }
      }
      
      // Request focus if needed - use microtask to allow UI to update first
      if (!focusNode.hasFocus) {
        Future.microtask(() => focusNode.requestFocus());
      }
    } catch (e) {
      _logger.error('Error restoring focus: $e');
      // Try to focus on the document anyway
      Future.microtask(() => focusNode.requestFocus());
    }
  }
  
  // Force immediate content commit for all blocks
  @override
  void commitAllContent() {
    _logger.debug('Committing content for all blocks');
    
    // First commit any uncommitted nodes
    _commitUncommittedNodes();
    
    // Check for deleted blocks (in original but not current)
    _checkForDeletedBlocks();
    
    // Then commit content for all current blocks
    for (final blockId in getCurrentBlockIds()) {
      _commitContentForBlock(blockId);
    }
  }
  
  // Check for blocks that were deleted during editing
  void _checkForDeletedBlocks() {
    // Map current blocks for lookup
    final Map<String, Block> currentBlocksMap = {
      for (var block in _blocks) block.id: block
    };
    
    // Check original blocks against current blocks
    for (final originalBlock in _originalBlocks) {
      if (!currentBlocksMap.containsKey(originalBlock.id)) {
        // This block was deleted
        _logger.info('Block was deleted during editing: ${originalBlock.id}');
        _onBlockDeleted?.call(originalBlock.id);
        
        // Remove from server cache
        _serverBlockCache.remove(originalBlock.id);
      }
    }
  }
  
  // Update server cache with a single block
  void updateServerCache(Block block) {
    _serverBlockCache[block.id] = block;
    
    // Clear modification flag since we just got an updated version from server
    _documentBuilder.clearModificationTracking(block.id);
  }
  
  // Request focus on the editor
  @override
  void requestFocus() {
    if (!_documentBuilder.focusNode.hasFocus) {
      _logger.debug('Requesting focus for editor');
      _documentBuilder.focusNode.requestFocus();
    }
  }
  
  // Add this property to expose user-modified blocks
  @override
  Set<String> get userModifiedBlockIds => _documentBuilder.userModifiedBlockIds;
  
  // Mark a block as modified by the user
  @override
  void markBlockAsModified(String blockId) {
    _documentBuilder.markBlockAsModified(blockId);
  }
  
  /// Sets focus to a specific block by ID
  @override
  void setFocusToBlock(String blockId) {
    // Find the block index
    final int blockIndex = blocks.indexWhere((block) => block.id == blockId);
    if (blockIndex >= 0) {
      // Notify listeners that we want to focus on this specific block
      _focusRequestedBlockId = blockId;
      notifyListeners();
    }
  }

  // Add this property to track which block should receive focus
  String? _focusRequestedBlockId;

  /// Gets the ID of the block that should receive focus, then clears it
  @override
  String? consumeFocusRequest() {
    final String? blockId = _focusRequestedBlockId;
    _focusRequestedBlockId = null; // Clear after consumption
    return blockId;
  }
  
  // Create a new block
  @override
  Future<Block> createBlock(String type) async {
    _logger.info('Creating new block of type: $type');
    
    if (_noteId == null) {
      throw Exception('Cannot create block: noteId is null');
    }
    
    // Calculate order for new block 
    double order = 1.0;
    if (_blocks.isNotEmpty) {
      // Place it at the end by default
      order = _blocks.map((b) => b.order).reduce((a, b) => a > b ? a : b) + 1.0;
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
    _blocks.add(block);
    
    // Add to server cache
    _serverBlockCache[block.id] = block;
    
    // Update document with new block
    _updatingDocument = true;
    try {
      final nodes = _documentBuilder.createNodesFromBlock(block);
      for (final node in nodes) {
        document.add(node);
        _documentBuilder.nodeToBlockMap[node.id] = block.id;
      }
    } finally {
      _updatingDocument = false;
    }
    
    notifyListeners();
    return block;
  }
      
  @override
  void dispose() {
    _logger.debug('Disposing rich text editor provider');
    // Make sure all content is saved before disposing
    if (_isActive) {
      commitAllContent();
    }
    
    // Try to ensure all blocks get created before disposing
    _commitUncommittedNodes();
    
    _documentBuilder.removeDocumentContentListener(_documentChangeListener);
    _documentBuilder.removeDocumentStructureListener(_documentStructureChangeListener);
    _documentBuilder.focusNode.removeListener(_handleFocusChange);
    _documentBuilder.dispose();
    super.dispose();
  }

  // BasePresenter implementation
  bool get isLoading => _isLoading;
  
  bool get isInitialized => _isInitialized;
  
  String? get errorMessage => _errorMessage;
  
  @override
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
  
  // Interface setter implementations
  @override
  set onBlockContentChanged(void Function(String blockId, dynamic content)? callback) {
    _onBlockContentChanged = callback;
  }
  
  @override
  set onBlockDeleted(void Function(String blockId)? callback) {
    _onBlockDeleted = callback;
  }
  
  @override
  set onMultiBlockOperation(void Function(List<String> blockIds)? callback) {
    _onMultiBlockOperation = callback;
  }
  
  @override
  set onFocusLost(void Function()? callback) {
    _onFocusLost = callback;
  }

  @override
  bool get isActive => _isActive;

  // Implement addBlocks method required by the interface
  @override
  void addBlocks(List<Block> blocks) {
    _logger.info('Adding blocks: received ${blocks.length} new blocks');
    
    if (blocks.isEmpty) return;
    
    // Update server cache with new blocks
    for (final block in blocks) {
      _serverBlockCache[block.id] = block;
      registerServerBlock(block);
    }
    
    // Get current selection and focus state to preserve during update
    final currentSelection = composer.selection;
    final hasFocus = focusNode.hasFocus;
    
    // Create map for efficient lookups
    final Map<String, Block> existingBlocksMap = {
      for (var block in _blocks) block.id: block
    };
    
    // Filter out blocks that we already have
    final List<Block> newBlocks = blocks
        .where((block) => !existingBlocksMap.containsKey(block.id))
        .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
    
    if (newBlocks.isEmpty) {
      _logger.debug('No new blocks to add, skipping update');
      return;
    }
    
    // Add the new blocks to our list
    _blocks.addAll(newBlocks);
    
    // Sort blocks by order
    _blocks.sort((a, b) => a.order.compareTo(b.order));
    
    // Create nodes for these blocks and add them to the document
    _updatingDocument = true;
    try {
      for (final block in newBlocks) {
        final nodes = _documentBuilder.createNodesFromBlock(block);
        for (final node in nodes) {
          document.add(node);
          _documentBuilder.nodeToBlockMap[node.id] = block.id;
        }
      }
    } finally {
      _updatingDocument = false;
    }
    
    // Restore focus if needed
    if (hasFocus && currentSelection != null) {
      Future.microtask(() {
        restoreFocus(currentSelection);
      });
    }
    
    notifyListeners();
  }
}
