import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart' hide Logger;
import '../models/block.dart';
import '../utils/logger.dart';
import '../services/base_service.dart';
import '../providers/block_provider.dart';
import '../utils/document_builder.dart';

/// Provider for managing the state of a full-page rich text editor that combines multiple blocks
class RichTextEditorProvider with ChangeNotifier {
  final Logger _logger = Logger('RichTextEditorProvider');
  
  // Document mapper handles all SuperEditor document operations
  late DocumentBuilder _documentBuilder;
  
  // Callback when content changes for specific block
  final Function(String blockId, Map<String, dynamic> content)? onBlockContentChanged;
  // Callback when content is deleted across multiple blocks
  final Function(List<String> blockIds)? onMultiBlockOperation;
  // Callback when a block should be deleted
  final Function(String blockId)? onBlockDeleted;
  // Callback when blocks should be merged
  final Function(String sourceBlockId, String targetBlockId, Map<String, dynamic> mergedContent)? onBlocksMerged;
  // Callback when focus is lost
  final Function()? onFocusLost;
  
  // Add current note ID to track which note blocks belong to
  final String noteId;
  
  // Add direct reference to BlockProvider for creating blocks
  final BlockProvider _blockProvider;

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
  
  // Add active state tracking
  bool _isActive = false;
  
  // Content update debouncer
  DateTime _lastEdit = DateTime.now();
  String? _currentEditingBlockId;
  
  // Flag to prevent recursive document updates
  bool _updatingDocument = false;
  
  // Standard constructor with callback parameters
  RichTextEditorProvider({
    required List<Block> blocks,
    required this.noteId,
    this.onBlockContentChanged,
    this.onMultiBlockOperation,
    this.onBlockDeleted,
    this.onBlocksMerged,
    this.onFocusLost,
    BlockProvider? blockProvider,
  }) : _blockProvider = blockProvider ?? ServiceLocator.get<BlockProvider>() {
    _blocks = List.from(blocks);
    // Store original blocks for later comparison
    _originalBlocks.addAll(blocks); 
    _initialize();
  }
  
  // Convenience getters that access document mapper properties
  MutableDocument get document => _documentBuilder.document;
  MutableDocumentComposer get composer => _documentBuilder.composer;
  Editor get editor => _documentBuilder.editor;
  FocusNode get focusNode => _documentBuilder.focusNode;
  List<Block> get blocks => List.unmodifiable(_blocks);
  
  // Standardized activate/deactivate methods
  void activate() {
    _isActive = true;
    _logger.info('RichTextEditorProvider activated');
    
    // Register document event to capture split paragraph events
    _documentBuilder.addDocumentStructureListener(_documentStructureChangeListener);
  }

  void deactivate() {
    _isActive = false;
    _logger.info('RichTextEditorProvider deactivated');
    
    // Commit all content before deactivating
    commitAllContent();
    
    // Remove document structure listener
    _documentBuilder.removeDocumentStructureListener(_documentStructureChangeListener);
  }
  
  // Add resetState for consistency
  void resetState() {
    _logger.info('Resetting RichTextEditorProvider state');
    // Clear blocks
    _blocks.clear();
    _originalBlocks.clear();
    _isActive = false;
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
    
    // Call the deletion handler to delete on server
    if (onBlockDeleted != null) {
      onBlockDeleted!(blockId);
    } else {
      // If no handler, try to delete directly
      _blockProvider.deleteBlock(blockId);
    }
  }
  
  // Create a server block for a new node created in the editor
  Future<void> _createBlockForNode(String nodeId, DocumentNode node) async {
    try {
      _logger.info('Creating block for new node $nodeId');
      
      // Determine block type based on node
      String blockType = 'text';
      if (node is ParagraphNode) {
        final blockTypeAttr = node.metadata['blockType'];
        if (blockTypeAttr == 'heading') {
          blockType = 'heading';
        } else if (blockTypeAttr == 'code') {
          blockType = 'code';
        }
      } else if (node is ListItemNode) {
        blockType = 'checklist';
      }
      
      // Extract content from node using the mapper
      final Map<String, dynamic> content = _extractNodeContentForApi(node);
      
      // Calculate a reasonable order value
      int order = await _documentBuilder.calculateOrderForNewNode(nodeId, _blocks);
      
      _logger.debug('Creating block of type $blockType with order $order');
      
      // Create block through BlockProvider
      final block = await _blockProvider.createBlock(
        noteId, 
        content,
        blockType,
        order
      );
      
      // Update our mappings
      _documentBuilder.nodeToBlockMap[nodeId] = block.id;
      _blocks.add(block);
      
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
    
    if (node is ParagraphNode) {
      // Basic text content
      content['text'] = node.text.toPlainText();
      
      // Extract spans/formatting information
      final spans = _documentBuilder.extractSpansFromAttributedText(node.text);
      if (spans.isNotEmpty) {
        content['spans'] = spans;
      }
      
      // Add type-specific properties
      if (node.metadata['blockType'] == 'heading') {
        content['level'] = node.metadata['headingLevel'] ?? 1;
      } else if (node.metadata['blockType'] == 'code') {
        content['language'] = 'plain';
      }
    } else if (node is ListItemNode) {
      content['text'] = node.text.toPlainText();
      content['checked'] = node.type == ListItemType.ordered;
      
      // Extract spans for list items as well
      final spans = _documentBuilder.extractSpansFromAttributedText(node.text);
      if (spans.isNotEmpty) {
        content['spans'] = spans;
      }
    }
    
    return content;
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
      onMultiBlockOperation?.call(_affectedBlockIds.toList());
      
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
    final originalBlock = _blocks.firstWhere((b) => b.id == blockId);
    
    // Extract content based on node type using the mapper
    Map<String, dynamic> content = _documentBuilder.extractContentFromNode(node, blockId, originalBlock);
    
    // Send content update
    onBlockContentChanged?.call(blockId, content);
    _currentEditingBlockId = null;
  }
  
  // Delete a block
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
    
    // Notify callback
    onBlockDeleted?.call(blockId);
    
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
      
      onFocusLost?.call();
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
  void updateBlocks(List<Block> blocks, {
    bool preserveFocus = false,
    DocumentSelection? savedSelection
  }) {
    _logger.info('Updating blocks: received ${blocks.length}, current ${_blocks.length}');
    
    if (_blocks.isEmpty && blocks.isNotEmpty) {
      // Initial load - just populate the document
      _blocks = List.from(blocks);
      _documentBuilder.populateDocumentFromBlocks(_blocks);
      notifyListeners();
      return;
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
      
      // Store focused block ID for restoring position
      String? focusedBlockId;
      if (currentSelection != null) {
        final nodeId = currentSelection.extent.nodeId;
        if (nodeId != null) {
          focusedBlockId = _documentBuilder.nodeToBlockMap[nodeId];
        }
      }
      
      // Use special document population that tries to preserve focus
      _documentBuilder.populateDocumentFromBlocks(_blocks);
      
      // Restore focus with correct reason
      if (preserveFocus && currentSelection != null && hasFocus) {
        Future.microtask(() {
          // Try to restore to the original selection with proper reason
          restoreFocus(currentSelection);
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

  // Restore focus to a previous position
  void restoreFocus(DocumentSelection selection) {
    try {
      final position = selection.extent;
      final nodeId = position.nodeId;
      if (nodeId != null) {
        // Find the node in the document
        final node = document.getNodeById(nodeId);
        if (node != null) {
          // Always use contentChange when the reason is programmatic content loading
          // This ensures the selection history behaves correctly
          composer.setSelectionWithReason(
            selection,
            SelectionReason.contentChange,
          );
          
          // Request focus if needed
          if (!focusNode.hasFocus) {
            focusNode.requestFocus();
          }
        }
      }
    } catch (e) {
      _logger.error('Error restoring focus: $e');
    }
  }
  
  // Force immediate content commit for all blocks
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
        onBlockDeleted?.call(originalBlock.id);
      }
    }
  }
  
  // Request focus on the editor
  void requestFocus() {
    if (!_documentBuilder.focusNode.hasFocus) {
      _logger.debug('Requesting focus for editor');
      _documentBuilder.focusNode.requestFocus();
    }
  }
  
  /// Sets focus to a specific block by ID
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
  String? consumeFocusRequest() {
    final String? blockId = _focusRequestedBlockId;
    _focusRequestedBlockId = null; // Clear after consumption
    return blockId;
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
}
