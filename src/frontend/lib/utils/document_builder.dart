import 'package:flutter/material.dart';
import 'package:owlistic/utils/data_converter.dart';
import 'package:super_editor/super_editor.dart' hide Logger;
import 'package:owlistic/models/block.dart';
import 'package:owlistic/utils/logger.dart';
import 'package:owlistic/utils/attributed_text_utils.dart';
import 'package:owlistic/utils/block_node_mapping.dart';

/// Class that handles mapping between Blocks and SuperEditor DocumentNodes
class DocumentBuilder {
  final Logger _logger = Logger('DocumentBuilder');
  
  // Add instance of AttributedTextUtils
  final AttributedTextUtils _attributedTextUtils = AttributedTextUtils();
  
  // Add BlockNodeMapping instance
  final BlockNodeMapping _blockNodeMapping = BlockNodeMapping();
  
  // Document components
  late MutableDocument document;
  late MutableDocumentComposer composer;
  late Editor editor;
  late FocusNode focusNode;
  
  // Document layout key for accessing the document layout
  final GlobalKey documentLayoutKey = GlobalKey();
  
  // Document scroller for programmatic scrolling
  late DocumentScroller documentScroller;
  
  // Track last known node count to detect new nodes
  int _lastKnownNodeCount = 0;
  
  // For tracking changes in the document structure
  List<String> _lastKnownNodeIds = [];
  
  // Flag to prevent recursive document updates
  bool _updatingDocument = false;
  
  // Last known selection data for robust position restoration
  String? _lastKnownNodeId;
  int? _lastKnownOffset;
  DocumentSelection? _lastKnownSelection;
  
  // Current editing block ID and timestamp for debouncing
  String? _currentEditingBlockId;
  final DateTime _lastEdit = DateTime.now();
  
  // Callback for updating block content on the server
  Function(String blockId, Map<String, dynamic> content, {String? type, bool immediate})? onUpdateBlockContent;
  
  // Get the set of blocks that were explicitly modified by user interaction
  Set<String> get userModifiedBlockIds => _blockNodeMapping.userModifiedBlockIds;
  
  // Map of node IDs to block IDs (read-only access)
  Map<String, String> get nodeToBlockMap => _blockNodeMapping.nodeToBlockMap;
  
  // Uncommitted nodes map (read-only access)
  Map<String, DateTime> get uncommittedNodes => _blockNodeMapping.uncommittedNodes;
  
  DocumentBuilder() {
    _initialize();
  }
  
  void _initialize() {
    // Create an empty document first
    document = MutableDocument();
    
    // Create composer
    composer = MutableDocumentComposer();
    
    // Create document scroller
    documentScroller = DocumentScroller();
    
    // Create editor with our document and composer
    editor = createDefaultDocumentEditor(document: document, composer: composer);
    
    // Create focus node
    focusNode = FocusNode();
    
    // Store initial node IDs for tracking structure changes
    _lastKnownNodeIds = document.map((node) => node.id).toList();
    _lastKnownNodeCount = document.length;
  }
  
  
  void dispose() {
    // Dispose of resources
    focusNode.dispose();
    composer.dispose();
    documentScroller.detach();
  }
  
  // Add document structure change listener to detect new/deleted nodes
  void addDocumentStructureListener(void Function(dynamic) listener) {
    document.addListener(listener);
  }
  
  void removeDocumentStructureListener(void Function(dynamic) listener) {
    document.removeListener(listener);
  }
  
  // Add content change listener
  void addDocumentContentListener(void Function(dynamic) listener) {
    document.addListener(listener);
  }
  
  void removeDocumentContentListener(DocumentChangeListener listener) {
    document.removeListener(listener);
  }
  
  // Insert a new node into the document
  void insertNode(DocumentNode node) {
    try {
      document.add(node);
      _logger.info('Node ${node.id} inserted into the document');
    } catch (e) {
      _logger.error('Error inserting node ${node.id}: $e');
    }
  }

  // Delete a node from the document by its ID
  void deleteNode(String nodeId) {
    try {
      final node = document.getNodeById(nodeId);
      if (node != null) {
        document.deleteNode(node.id);
        _logger.info('Node $nodeId deleted from the document');
      } else {
        _logger.warning('Node $nodeId not found for deletion');
      }
    } catch (e) {
      _logger.error('Error deleting node $nodeId: $e');
    }
  }

  // Convert blocks to document nodes and populate the document
  void populateDocumentFromBlocks(List<Block> blocks, {bool markAsModified = true}) {
    if (_updatingDocument) {
      _logger.debug('Already updating document, skipping');
      return;
    }
    
    _updatingDocument = true;
    _logger.info('Populating document with ${blocks.length} blocks');
    
    try {
      // Remember current selection with enhanced state capture
      String? previousNodeId;
      int? previousTextOffset;
      DocumentPosition? previousPosition;
      DocumentSelection? previousSelection;
      
      try {
        // Try to capture the current selection for restoration
        if (composer.selection != null) {
          previousSelection = composer.selection;
          previousNodeId = composer.selection?.extent.nodeId;
          if (composer.selection?.extent.nodePosition is TextNodePosition) {
            previousTextOffset = (composer.selection!.extent.nodePosition as TextNodePosition).offset;
            previousPosition = composer.selection!.extent;
          }
        } else if (_lastKnownSelection != null) {
          // Fall back to last known good selection if current selection is null
          previousSelection = _lastKnownSelection;
          previousNodeId = _lastKnownNodeId;
          previousTextOffset = _lastKnownOffset;
          if (_lastKnownNodeId != null && _lastKnownOffset != null) {
            previousPosition = DocumentPosition(
              nodeId: _lastKnownNodeId!,
              nodePosition: TextNodePosition(offset: _lastKnownOffset!),
            );
          }
        }
        
        // Capture block ID of the focused node to help with position restoration
        String? previousBlockId;
        if (previousNodeId != null) {
          previousBlockId = _blockNodeMapping.getBlockIdForNode(previousNodeId);
          _logger.debug('Saving position in block: $previousBlockId, node: $previousNodeId, offset: $previousTextOffset');
        }
      } catch (e) {
        _logger.warning('Error capturing selection state: $e');
      }
      
      // Clear document and mapping with error handling
      try {
        final nodeIds = document.map((node) => node.id).toList();
        for (final nodeId in nodeIds) {
          deleteNode(nodeId);
        }
        _blockNodeMapping.clearMappings();
      } catch (e) {
        _logger.error('Error clearing document: $e');
        // Try to recreate document if clearing fails
        _initialize();
      }
      
      // Sort blocks by order
      final sortedBlocks = List.from(blocks)
        ..sort((a, b) => a.order.compareTo(b.order));
      
      _logger.debug('Creating document nodes for ${sortedBlocks.length} blocks');
      // Create node based on block type
      // Keep track of created nodes by block ID to help with selection restoration
      final Map<String, String> blockToNodeMap = {};
      
      // Convert each block to a document node with error handling
      for (final block in sortedBlocks) {
        try {
          final nodes = createNodesFromBlock(block);
          
          // Add all nodes to document
          for (final node in nodes) {
            try {
              insertNode(node);
              // Map node ID to block ID
              _blockNodeMapping.linkNodeToBlock(node.id, block.id);
              blockToNodeMap[block.id] = node.id;
              
              // Register this block as from server
              registerServerBlock(block, node.id);
              
              // Only mark blocks as modified if explicitly requested
              // This allows us to differentiate between initial load and user edits
              if (markAsModified) {
                _blockNodeMapping.markBlockAsModified(block.id);
              }
              
            } catch (e) {
              _logger.error('Error adding node to document: $e');
              // Continue with next node
            }
          }
        } catch (e) {
          _logger.error('Error creating node for block ${block.id}: $e');
          // Continue with next block
        }
      }
      
      // If document is empty after population attempts, add an empty paragraph
      // to ensure the document is never completely empty
      if (document.isEmpty) {
        try {
          _logger.warning('Document is empty after population, adding default node');
          final defaultNode = ParagraphNode(
            id: Editor.createNodeId(),
            text: AttributedText('')
          );
          insertNode(defaultNode);
        } catch (e) {
          _logger.error('Error adding default node: $e');
        }
      }
      
      // Restore selection with new fail-safe mechanisms
      try {
        if (previousSelection != null) {
          _logger.debug('Attempting to restore previous selection');
          
          // Try different strategies to restore position
          bool positionRestored = false;
          
          // STRATEGY 1: Try to find the same node ID if it still exists
          if (previousNodeId != null && document.getNodeById(previousNodeId) != null) {
            _logger.debug('Found exact previous node, restoring position');
            
            if (previousPosition != null) {
              // Verify the position is valid for the node type
              final node = document.getNodeById(previousNodeId);
              
              if (node is TextNode && previousPosition.nodePosition is TextNodePosition) {
                final textNode = node;
                final textPosition = previousPosition.nodePosition as TextNodePosition;
                // Ensure text offset is within bounds
                final safeOffset = textPosition.offset.clamp(0, textNode.text.length);
                
                // Use setSelectionWithReason instead of direct assignment
                composer.setSelectionWithReason(
                  DocumentSelection(
                    base: DocumentPosition(
                      nodeId: previousNodeId,
                      nodePosition: TextNodePosition(offset: safeOffset),
                    ),
                    extent: DocumentPosition(
                      nodeId: previousNodeId,
                      nodePosition: TextNodePosition(offset: safeOffset),
                    ),
                  ),
                  SelectionReason.contentChange
                );
                positionRestored = true;
              }
            }
          }
          
          // STRATEGY 2: Try to find a node mapping to the same block ID
          if (!positionRestored && previousNodeId != null) {
            final previousBlockId = _blockNodeMapping.getBlockIdForNode(previousNodeId);
            if (previousBlockId != null && blockToNodeMap.containsKey(previousBlockId)) {
              _logger.debug('Found different node for same block, restoring position');
              
              final newNodeId = blockToNodeMap[previousBlockId]!;
              final node = document.getNodeById(newNodeId);
              
              // Default to start of node if offset can't be preserved
              int safeOffset = 0;
              if (node is TextNode && previousTextOffset != null) {
                // Ensure offset is within bounds
                safeOffset = previousTextOffset.clamp(0, node.text.length);
              }
              
              // Use setSelectionWithReason instead of direct assignment
              composer.setSelectionWithReason(
                DocumentSelection(
                  base: DocumentPosition(
                    nodeId: newNodeId,
                    nodePosition: TextNodePosition(offset: safeOffset),
                  ),
                  extent: DocumentPosition(
                    nodeId: newNodeId,
                    nodePosition: TextNodePosition(offset: safeOffset),
                  ),
                ),
                SelectionReason.contentChange
              );
              positionRestored = true;
            }
          }
          
          // STRATEGY 3: If all else fails, position at the start of the document
          if (!positionRestored && document.isNotEmpty) {
            _logger.debug('Using fallback position at start of document');
            
            final firstNode = document.first;
            
            // Use setSelectionWithReason instead of direct assignment
            composer.setSelectionWithReason(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: firstNode.id,
                  nodePosition: const TextNodePosition(offset: 0),
                ),
                extent: DocumentPosition(
                  nodeId: firstNode.id,
                  nodePosition: const TextNodePosition(offset: 0),
                ),
              ),
              SelectionReason.contentChange
            );
          }
        }
      } catch (e) {
        _logger.error('Error restoring selection: $e');
        // Selection restoration failed, but document is still usable
      }
    } catch (e) {
      _logger.error('Error populating document: $e');
      // If overall population fails, try to ensure document isn't empty
      if (document.isEmpty) {
        try {
          final fallbackNode = ParagraphNode(
            id: Editor.createNodeId(),
            text: AttributedText('')
          );
          insertNode(fallbackNode);
        } catch (e) {
          _logger.error('Error adding fallback node: $e');
        }
      }
    } finally {
      _updatingDocument = false;
      
      // Update tracking properties
      _lastKnownNodeIds = document.map((node) => node.id).toList();
      _lastKnownNodeCount = document.length;
    }
  }

  // Check for document structure changes
  void checkDocumentStructureChanges({
    required Function(String) onNewNodeCreated,
    required Function(String) onNodeDeleted,
  }) {
    final currentNodeCount = document.length;
    final currentNodeIds = document.map((node) => node.id).toList();
    
    // If we have more nodes now than before, there might be new nodes
    if (currentNodeCount > _lastKnownNodeCount) {
      _logger.debug('Document node count changed: $_lastKnownNodeCount -> $currentNodeCount');
      
      // Find new nodes (present in current list but not in previous list)
      final newNodeIds = currentNodeIds.where((id) => !_lastKnownNodeIds.contains(id)).toList();
      
      if (newNodeIds.isNotEmpty) {
        _logger.info('Detected ${newNodeIds.length} new nodes: ${newNodeIds.join(', ')}');
        
        // Handle each new node
        for (final nodeId in newNodeIds) {
          onNewNodeCreated(nodeId);
        }
      }
    } 
    // If we have fewer nodes than before, there might be deleted nodes
    else if (currentNodeCount < _lastKnownNodeCount) {
      _logger.debug('Document node count decreased: $_lastKnownNodeCount -> $currentNodeCount');
      
      // Find deleted nodes (present in previous list but not in current list)
      final deletedNodeIds = _lastKnownNodeIds.where((id) => !currentNodeIds.contains(id)).toList();
      
      if (deletedNodeIds.isNotEmpty) {
        _logger.info('Detected ${deletedNodeIds.length} deleted nodes: ${deletedNodeIds.join(', ')}');
        
        // Handle each deleted node
        for (final nodeId in deletedNodeIds) {
          onNodeDeleted(nodeId);
        }
      }
    }
    
    // Update our last known state
    _lastKnownNodeIds = currentNodeIds;
    _lastKnownNodeCount = currentNodeCount;
  }
  
  // Handle newly created nodes (like from pressing Enter to split a paragraph)
  bool shouldCreateBlockForNode(String nodeId) {
    // Skip if this node is already mapped to a block
    if (_blockNodeMapping.getBlockIdForNode(nodeId) != null) {
      _logger.debug('Node $nodeId already mapped to a block, skipping');
      return false;
    }
    
    // Skip if we're already processing this node
    if (_blockNodeMapping.isNodeUncommitted(nodeId)) {
      _logger.debug('Node $nodeId is already being processed, skipping');
      return false;
    }
    
    // Get the node from the document
    final node = document.getNodeById(nodeId);
    if (node == null) {
      _logger.warning('Could not find node $nodeId in document');
      return false;
    }
    
    // Mark as uncommitted
    _blockNodeMapping.markNodeAsUncommitted(nodeId);
    return true;
  }
  
  // Calculate a fractional index order for a new node using midpoint between adjacent blocks
  Future<double> calculateOrderForNewNode(String nodeId, List<Block> blocks) async {
    // Get the position of this node in the document
    final nodeIndex = document.getNodeIndexById(nodeId); // Fallback value
    
    // If no blocks exist yet, use 1000 as starting point
    if (blocks.isEmpty) {
      return 1000.0;
    }
    
    // Sort blocks by order to find neighbors
    final sortedBlocks = List.from(blocks)..sort((a, b) => a.order.compareTo(b.order));
    
    // If this is the first node, put it before the first block
    if (nodeIndex == 0) {
      final firstBlockOrder = sortedBlocks.first.order;
      return firstBlockOrder - 10.0;
    }
    
    // If this is the last node, put it after the last block
    if (nodeIndex >= document.length - 1) {
      final lastBlockOrder = sortedBlocks.last.order;
      return lastBlockOrder + 10.0;
    }
    
    // Otherwise, find the blocks before and after this node
    // and place it between them using fractional indexing
    final prevNodeId = document.getNodeAt(nodeIndex - 1)?.id;
    final nextNodeId = document.getNodeAt(nodeIndex + 1)?.id;
    
    double prevOrder = 0;
    double nextOrder = 2000;
    
    // Find previous block's order
    if (prevNodeId != null) {
      final prevBlockId = _blockNodeMapping.getBlockIdForNode(prevNodeId);
      if (prevBlockId != null) {
        final prevBlock = blocks.firstWhere(
          (b) => b.id == prevBlockId,
          orElse: () => sortedBlocks.first,
        );
        prevOrder = prevBlock.order;
      }
    }
    
    // Find next block's order
    if (nextNodeId != null) {
      final nextBlockId = _blockNodeMapping.getBlockIdForNode(nextNodeId);
      if (nextBlockId != null) {
        final nextBlock = blocks.firstWhere(
          (b) => b.id == nextBlockId, 
          orElse: () => sortedBlocks.last,
        );
        nextOrder = nextBlock.order;
      }
    }
    
    // Calculate the midpoint for fractional indexing
    return prevOrder + ((nextOrder - prevOrder) / 2);
  }
  
  // Mark a block as locally modified to optimize server updates
  void markBlockAsModified(String blockId) {
    _blockNodeMapping.markBlockAsModified(blockId);
    _logger.debug('Block $blockId marked as explicitly modified by user');
  }
  
  /// Register a block as being fetched from the server
  /// This helps track which blocks should be considered as "server source of truth"
  void registerServerBlock(Block block, [String nodeId = '']) {
    _blockNodeMapping.registerServerBlock(block, nodeId);
  }

  /// Check if this block should be updated from the server version
  /// Returns true if the server version is newer than any local changes
  bool shouldUpdateFromServer(String blockId, Block serverBlock) {
    return _blockNodeMapping.shouldUpdateFromServer(blockId, serverBlock);
  }
  
  /// Check if we should send a block update to the server
  bool shouldSendBlockUpdate(String blockId, Block serverBlock) {
    // If not modified locally, don't send update
    if (!_blockNodeMapping.isBlockModifiedByUser(blockId)) {
      return false;
    }
    
    // Get node associated with this block
    String? nodeId = _blockNodeMapping.getNodeIdForBlock(blockId);
    if (nodeId == null) {
      _logger.debug('Block $blockId has no associated node, skipping update');
      return false;
    }
    
    // Get the node from document
    final node = document.getNodeById(nodeId);
    if (node == null) {
      _logger.debug('Node $nodeId not found in document, skipping update');
      return false;
    }
    
    // Check if content actually changed compared to server block
    if (hasNodeContentChanged(node, blockId, serverBlock)) {
      _logger.debug('Block $blockId content has changed, sending update');
      return true;
    } else {
      _logger.debug('Block $blockId content unchanged, skipping update');
      _blockNodeMapping.clearModificationTracking(blockId); // Clear modification flag since no real changes
      return false;
    }
  }
  
  // Clear modification tracking after successful update
  void clearModificationTracking(String blockId) {
    _blockNodeMapping.clearModificationTracking(blockId);
  }
  
  // Extract content from a node in the format expected by the API
  Map<String, dynamic> extractContentFromNode(DocumentNode node, String blockId, Block originalBlock) {
    // Initialize with strict format
    Map<String, dynamic> content = {'text': ''};
    Map<String, dynamic> metadata = {'_sync_source': 'block', 'block_id': blockId};
    
    // Extract metadata from original block
    if (originalBlock.metadata != null) {
      metadata.addAll(Map<String, dynamic>.from(originalBlock.metadata!));
    }
    
    if (node is ParagraphNode) {
      // ONLY text goes in content
      content['text'] = node.text.toPlainText();
      
      // Extract spans/formatting information for metadata
      final spans = _attributedTextUtils.extractSpansFromAttributedText(node.text);
      if (spans.isNotEmpty) {
        metadata['spans'] = spans;
      }
      
      // Extract node blockType for determining block.type 
      // DO NOT store blockType in metadata - it's a property of the block model
      final blockType = node.metadata['blockType'];
      String blockTypeStr = '';
      
      if (blockType is NamedAttribution) {
        blockTypeStr = blockType.id;
      } else if (blockType is String) {
        blockTypeStr = blockType;
      }
      
      // Extract specific metadata based on node type
      if (blockTypeStr.startsWith('heading')) {
        final levelStr = blockTypeStr.substring(7);
        final level = int.tryParse(levelStr) ?? 1;
        metadata['level'] = level;
      }
      else if (blockTypeStr == 'code') {
        metadata['language'] = node.metadata['language'] ?? 'plain';
      }
    } 
    else if (node is TaskNode) {
      content['text'] = node.text.toPlainText();
      
      // Task state in metadata
      metadata['is_completed'] = node.isComplete;
      
      // Extract spans
      final spans = _attributedTextUtils.extractSpansFromAttributedText(node.text);
      if (spans.isNotEmpty) {
        metadata['spans'] = spans;
      }
    } 
    else if (node is ListItemNode) {
      // ONLY text in content
      content['text'] = node.text.toPlainText();
      
      // List metadata
      metadata['listType'] = node.type == ListItemType.ordered ? 'ordered' : 'unordered';
      
      // Extract spans
      final spans = _attributedTextUtils.extractSpansFromAttributedText(node.text);
      if (spans.isNotEmpty) {
        metadata['spans'] = spans;
      }
    }
    
    return {
      'content': content,
      'metadata': metadata
    };
  }

  /// Extract content from a node in a standardized format for API usage
  Map<String, dynamic> extractNodeContent(DocumentNode node, Block? originalBlock) {
    // Initialize with a base structure
    Map<String, dynamic> content = {'text': ''};
    Map<String, dynamic> metadata = {'_sync_source': 'block'};
    
    // Preserve original metadata values if available
    if (originalBlock != null && originalBlock.metadata != null) {
      metadata = Map<String, dynamic>.from(originalBlock.metadata!);
      // Ensure _sync_source is present
      metadata['_sync_source'] = 'block';
    }
    
    if (node is ParagraphNode) {
      content['text'] = node.text.toPlainText();
      
      // Extract spans/formatting information
      final spans = _attributedTextUtils.extractSpansFromAttributedText(node.text);
      metadata['spans'] = spans; // Always include spans array
      
      // Process node blockType for determining block type
      final blockType = node.metadata['blockType'];
      String blockTypeStr = '';
      
      if (blockType is NamedAttribution) {
        blockTypeStr = blockType.id;
      } else if (blockType is String) {
        blockTypeStr = blockType;
      }
      
      // Handle specific block types - extract additional metadata but don't include blockType
      if (blockTypeStr.startsWith('heading')) {
        // Extract heading level from blockType like "heading1"
        final levelStr = blockTypeStr.substring(7);
        final level = DataConverter.parseIntSafely(levelStr) ?? 1;
        metadata['level'] = level;
      } 
      else if (blockTypeStr == 'code') {
        metadata['language'] = node.metadata['language'] ?? 'plain';
      }
    } 
    else if (node is TaskNode) {
      content['text'] = node.text.toPlainText();
      
      metadata['is_completed'] = node.isComplete;
      
      // Extract spans for formatting
      final spans = _attributedTextUtils.extractSpansFromAttributedText(node.text);
      metadata['spans'] = spans;
    } 
    else if (node is ListItemNode) {
      content['text'] = node.text.toPlainText();
      
      // Extract spans for list items
      final spans = _attributedTextUtils.extractSpansFromAttributedText(node.text);
      metadata['spans'] = spans;
      
      metadata['listType'] = node.type == ListItemType.ordered ? 'ordered' : 'unordered';
    }
    
    return {
      'content': content,
      'metadata': metadata
    };
  }

  // Creates nodes from a block with proper metadata handling
  List<DocumentNode> createNodesFromBlock(Block block) {
    final content = block.content;
    final metadata = block.metadata;
    String blockType = block.type;
    
    // Get text content (only thing that should be in content)
    final text = content['text']?.toString() ?? '';
    
    // Use block.type directly - don't look for blockType in metadata
    // This is because blockType is not a property of block.metadata
    
    // Create node based on block type
    switch (blockType) {
      case 'heading':
        // Get heading level from metadata
        final level = metadata != null ? metadata['level'] ?? 1 : 1;
        final levelInt = level is int ? level : int.tryParse(level.toString()) ?? 1;
        
        return [
          ParagraphNode(
            id: Editor.createNodeId(),
            text: _attributedTextUtils.createAttributedTextFromContent(text, {'metadata': metadata}),
            metadata: {
              'blockType': NamedAttribution("heading$levelInt"), 
            },
          ),
        ];
        
      case 'task':
        // Get completion status from metadata
        bool isCompleted = false;
        if (metadata != null && metadata.containsKey('is_completed')) {
          isCompleted = metadata['is_completed'] == true;
        }
        
        return [
          TaskNode(
            id: Editor.createNodeId(),
            text: _attributedTextUtils.createAttributedTextFromContent(text, {'metadata': metadata}),
            isComplete: isCompleted,
          ),
        ];
        
      case 'code':
        final language = metadata != null ? metadata['language']?.toString() ?? 'plain' : 'plain';
        return [
          ParagraphNode(
            id: Editor.createNodeId(),
            text: _attributedTextUtils.createAttributedTextFromContent(text, {'metadata': metadata}),
            metadata: {
              'blockType': const NamedAttribution("code"),
              'language': language
            },
          ),
        ];
        
      case 'text':
      default:
        return [
          ParagraphNode(
            id: Editor.createNodeId(),
            text: _attributedTextUtils.createAttributedTextFromContent(text, {'metadata': metadata}),
            metadata: const {'blockType': NamedAttribution("paragraph")},
          ),
        ];
    }
  }

  // New method: Create a node for a specific block and insert it at the right position
  void insertBlockNode(Block block, {int? index}) {
    final nodes = createNodesFromBlock(block);
    if (nodes.isEmpty) return;
    
    final node = nodes.first;
    
    // Map the node to the block
    _blockNodeMapping.linkNodeToBlock(node.id, block.id);
    
    // Insert at specific index if provided, otherwise add to end
    if (index != null && index >= 0 && index <= document.length) {
      _updatingDocument = true;
      try {
        document.insertNodeAt(index, node);
        _logger.info('Node inserted for block ${block.id} at position $index');
      } finally {
        _updatingDocument = false;
      }
    } else {
      insertNode(node);
    }
  }
  
  // New method: Delete a node for a specific block
  bool deleteBlockNode(String blockId) {
    // Find the node ID for this block
    String? nodeId = _blockNodeMapping.getNodeIdForBlock(blockId);
    
    if (nodeId != null) {
      _updatingDocument = true;
      try {
        document.deleteNode(nodeId);
        _blockNodeMapping.removeBlockMapping(blockId);
        _logger.info('Node deleted for block $blockId');
        return true;
      } catch (e) {
        _logger.error('Error deleting node for block $blockId: $e');
      } finally {
        _updatingDocument = false;
      }
    }
    return false;
  }
  
  // New method: Update a node for a specific block
  bool updateBlockNode(Block block) {
    // Find node for this block
    String? nodeId = _blockNodeMapping.getNodeIdForBlock(block.id);
    
    if (nodeId == null || nodeId.isEmpty) {
      // No nodes for this block - must be a new block
      _logger.debug('No existing node for block ${block.id}, will insert a new one');
      return false;
    }
    
    // Create new nodes from updated block
    final newNodes = createNodesFromBlock(block);
    if (newNodes.isEmpty) return false;
    
    try {
      // Replace the old node with the new one
      _updatingDocument = true;
      document.replaceNodeById(nodeId, newNodes.first);
      
      // Update mapping
      _blockNodeMapping.removeNodeMapping(nodeId);
      _blockNodeMapping.linkNodeToBlock(newNodes.first.id, block.id);
      
      _logger.debug('Node updated for block ${block.id}');
      return true;
    } catch (e) {
      _logger.error('Error updating node for block ${block.id}: $e');
      return false;
    } finally {
      _updatingDocument = false;
    }
  }
  
  // New method: Find the index where a block should be inserted based on order
  int findInsertIndexForBlock(Block block, List<Block> allBlocks) {
    // Get all blocks that have nodes
    final nodeBlockIds = _blockNodeMapping.nodeToBlockMap.values.toSet().toList();
    
    // If no blocks with nodes, insert at the beginning
    if (nodeBlockIds.isEmpty) {
      return 0;
    }
    
    // Find blocks that have nodes and sort by order
    final visibleBlocks = allBlocks
        .where((b) => nodeBlockIds.contains(b.id))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    
    // Find the first block with order > new block's order
    for (int i = 0; i < visibleBlocks.length; i++) {
      if (block.order < visibleBlocks[i].order) {
        // Find node index for this block
        final targetNodeId = _blockNodeMapping.getNodeIdForBlock(visibleBlocks[i].id);
        if (targetNodeId != null) {
          final index = document.getNodeIndexById(targetNodeId);
          return index;
        }
      }
    }
    
    // If no suitable position found, add to end
    return document.length;
  }
  
  // New method: Move a node for a block to a new position
  bool moveBlockNode(String blockId, int targetIndex) {
    // Find the node ID for this block
    String? nodeId = _blockNodeMapping.getNodeIdForBlock(blockId);
    
    if (nodeId != null) {
      final currentIndex = document.getNodeIndexById(nodeId);
      if (currentIndex != targetIndex) {
        _updatingDocument = true;
        try {
          final node = document.getNodeById(nodeId)!;
          document.deleteNode(nodeId);
          
          // Adjust target index if needed (if moving forward)
          final adjustedIndex = targetIndex > currentIndex ? targetIndex - 1 : targetIndex;
          document.insertNodeAt(adjustedIndex, node);
          
          _logger.info('Node for block $blockId moved from $currentIndex to $adjustedIndex');
          return true;
        } catch (e) {
          _logger.error('Error moving node for block $blockId: $e');
        } finally {
          _updatingDocument = false;
        }
      }
    }
    return false;
  }
  
  // Simplified method to handle incremental document updates
  void updateDocumentWithBlocks(List<Block> blocks, List<Block> allBlocks) {
    if (blocks.isEmpty) return;
    
    // Save current selection state
    final currentSelection = composer.selection;
    final hadFocus = focusNode.hasFocus;
    
    _updatingDocument = true;
    try {
      for (final block in blocks) {
        // Check if a node for this block already exists
        bool nodeExists = false;
        _blockNodeMapping.nodeToBlockMap.forEach((nodeId, blockId) {
          if (blockId == block.id) {
            nodeExists = true;
          }
        });
        
        if (nodeExists) {
          // Update existing node
          updateBlockNode(block);
        } else {
          // Insert new node at the correct position
          final insertIndex = findInsertIndexForBlock(block, allBlocks);
          insertBlockNode(block, index: insertIndex);
        }
      }
      
      // After updates, restore selection if it was lost
      if (currentSelection != null && composer.selection == null) {
        tryRestoreSelection(currentSelection);
        
        // If selection restoration failed but we had focus, at least restore focus
        if (hadFocus && !focusNode.hasFocus) {
          focusNode.requestFocus();
        }
      }
    } finally {
      _updatingDocument = false;
    }
  }

  // Find the best node to place cursor at when restoring selection fails
  DocumentPosition? findBestAlternativePosition() {
    try {
      if (document.isEmpty) {
        return null;
      }
      
      // Try several strategies to find a valid position
      
      // 1. If we have a lastKnownNodeId and it exists, use it
      if (_lastKnownNodeId != null && document.getNodeById(_lastKnownNodeId!) != null) {
        final node = document.getNodeById(_lastKnownNodeId!);
        if (node is TextNode) {
          // Place cursor at same position or at end if text is shorter now
          final safeOffset = (_lastKnownOffset ?? 0).clamp(0, node.text.length);
          return DocumentPosition(
            nodeId: _lastKnownNodeId!,
            nodePosition: TextNodePosition(offset: safeOffset),
          );
        }
      }
      
      // 2. Try first node in document
      final firstNode = document.first;
      if (firstNode is TextNode) {
        return DocumentPosition(
          nodeId: firstNode.id,
          nodePosition: const TextNodePosition(offset: 0),
        );
      }
      
      // 3. Try any text node
      for (final node in document) {
        if (node is TextNode) {
          return DocumentPosition(
            nodeId: node.id,
            nodePosition: const TextNodePosition(offset: 0),
          );
        }
      }
      
      // No suitable position found
      return null;
    } catch (e) {
      _logger.error('Error finding alternative cursor position: $e');
      return null;
    }
  }
  
  // Attempt to restore selection safely
  bool tryRestoreSelection(DocumentSelection? selection) {
    if (selection == null) {
      return false;
    }
    
    try {
      // Verify that the nodes exist
      final baseNodeExists = document.getNodeById(selection.base.nodeId) != null;
      final extentNodeExists = document.getNodeById(selection.extent.nodeId) != null;
      
      if (!baseNodeExists || !extentNodeExists) {
        _logger.warning('Node(s) in selection no longer exist, using fallback');
        return false;
      }
      
      // Validate positions for each node
      bool validBase = true;
      bool validExtent = true;
      
      // Validate base position
      if (selection.base.nodePosition is TextNodePosition) {
        final node = document.getNodeById(selection.base.nodeId);
        if (node is TextNode) {
          final position = selection.base.nodePosition as TextNodePosition;
          if (position.offset < 0 || position.offset > node.text.length) {
            validBase = false;
          }
        } else {
          validBase = false;
        }
      }
      
      // Validate extent position
      if (selection.extent.nodePosition is TextNodePosition) {
        final node = document.getNodeById(selection.extent.nodeId);
        if (node is TextNode) {
          final position = selection.extent.nodePosition as TextNodePosition;
          if (position.offset < 0 || position.offset > node.text.length) {
            validExtent = false;
          }
        } else {
          validExtent = false;
        }
      }
      
      if (!validBase || !validExtent) {
        _logger.warning('Invalid position in selection, using fallback');
        return false;
      }
      
      // Selection is valid, restore it using setSelectionWithReason
      composer.setSelectionWithReason(selection, SelectionReason.contentChange);
      return true;
    } catch (e) {
      _logger.error('Error trying to restore selection: $e');
      return false;
    }
  }
  
  // Create a safe copy of a potentially problematic document selection
  DocumentSelection? createSafeSelectionCopy(DocumentSelection? selection) {
    if (selection == null) {
      return null;
    }
    
    try {
      // Create a copy of base position
      DocumentPosition? safeBase;
      if (selection.base.nodePosition is TextNodePosition) {
        safeBase = DocumentPosition(
          nodeId: selection.base.nodeId,
          nodePosition: TextNodePosition(
            offset: (selection.base.nodePosition as TextNodePosition).offset
          ),
        );
      }
      
      // Create a copy of extent position
      DocumentPosition? safeExtent;
      if (selection.extent.nodePosition is TextNodePosition) {
        safeExtent = DocumentPosition(
          nodeId: selection.extent.nodeId,
          nodePosition: TextNodePosition(
            offset: (selection.extent.nodePosition as TextNodePosition).offset
          ),
        );
      }
      
      if (safeBase != null && safeExtent != null) {
        return DocumentSelection(
          base: safeBase,
          extent: safeExtent,
        );
      }
      
      return null;
    } catch (e) {
      _logger.error('Error creating safe selection copy: $e');
      return null;
    }
  }
  
  /// Check if the content of a node has changed compared to its corresponding block
  bool hasNodeContentChanged(DocumentNode node, String blockId, Block block) {
    final extractedData = extractContentFromNode(node, blockId, block);
    final content = extractedData['content'];
    final metadata = extractedData['metadata'];
    
    // Compare text content only from content object
    if (block.content['text'] != content['text']) {
      _logger.debug('Block $blockId text changed');
      return true;
    }
    
    // For task blocks, check completion status from metadata
    if (block.type == 'task' && block.metadata != null && metadata['is_completed'] != block.metadata!['is_completed']) {
      _logger.debug('Block $blockId task completion status changed');
      return true;
    }
    
    // Check spans in metadata
    final blockSpans = block.metadata != null ? block.metadata!['spans'] : null;
    final nodeSpans = metadata['spans'];
    
    if ((blockSpans == null && nodeSpans != null && nodeSpans.isNotEmpty) ||
        (blockSpans != null && blockSpans.isNotEmpty && nodeSpans == null) ||
        (blockSpans != null && nodeSpans != null && blockSpans.toString() != nodeSpans.toString())) {
      _logger.debug('Block $blockId spans changed');
      return true;
    }
    
    return false;
  }

  /// Gets the position information for a node from a document layout
  /// Returns the vertical offset of the node which can be used for scrolling
  double? getNodePosition(String nodeId) {
    try {
      final documentLayoutEditable = editor.context.find<DocumentLayoutEditable>(Editor.layoutKey);
      final documentLayout = documentLayoutEditable.documentLayout;
      
      final node = document.getNodeById(nodeId);
      if (node == null) {
        return null;
      }
      
      // Create a document position at the beginning of the node
      final documentPosition = DocumentPosition(
        nodeId: nodeId,
        nodePosition: node.beginningPosition,
      );
      
      // Get the rect for this position
      final rect = documentLayout.getRectForPosition(documentPosition);
      if (rect == null) {
        return null;
      }
      
      // Return the top offset of the rect
      return rect.top;
    } catch (e) {
      _logger.error('Error getting node position for $nodeId: $e');
      return null;
    }
  }
  
  // Create Super Editor with configured components and keyboard handlers
  Widget createSuperEditor({
    required bool readOnly,
    ScrollController? scrollController,
    ThemeData? themeData,
  }) {
    // Define light stylesheet (default)
    final lightStylesheet = defaultStylesheet.copyWith();
    
    // Define dark stylesheet with adjusted colors
    final darkStylesheet = lightStylesheet.copyWith(
      addRulesAfter: [
        // Make all text white/light gray
        StyleRule(
          BlockSelector.all, (doc, docNode) {
            return {
              Styles.textStyle: const TextStyle(
                color: Color(0xFFEEEEEE),
                fontSize: 18,
                height: 1.4,
              ),
            };
          },
        ),
        // Adjust heading colors for dark mode
        StyleRule(
          const BlockSelector("header1"), (doc, docNode) {
            return {
              Styles.textStyle: const TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 38,
                fontWeight: FontWeight.bold,
              ),
            };
          },
        ),
        StyleRule(
          const BlockSelector("header2"), (doc, docNode) {
            return {
              Styles.textStyle: const TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            };
          },
        ),
        StyleRule(
          const BlockSelector("header3"), (doc, docNode) {
            return {
              Styles.textStyle: const TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            };
          },
        ),
        // Adjust blockquote for dark mode
        StyleRule(
          const BlockSelector("blockquote"), (doc, docNode) {
            return {
              Styles.textStyle: const TextStyle(
                color: Color(0xFFA0A0A0), // Lighter gray for blockquotes
                fontSize: 20,
                fontWeight: FontWeight.bold,
                height: 1.4,
              ),
            };
          },
        ),
      ],
      // Customize how text appears when selected in dark mode
      selectedTextColorStrategy: ({required Color originalTextColor, required Color selectionHighlightColor}) {
        // In dark mode, make the selected text black for better contrast against blue selection
        return Colors.white;
      },
      // Use the same selection color defined in light stylesheet, but can be customized if needed
    );
    
    // Determine which stylesheet to use based on theme brightness
    final brightness = themeData?.brightness ?? Brightness.light;
    final stylesheet = brightness == Brightness.dark ? darkStylesheet : lightStylesheet;
    
    return SuperEditor(
      editor: editor,
      focusNode: focusNode,
      documentLayoutKey: documentLayoutKey,
      scrollController: scrollController,
      stylesheet: stylesheet,
    );
  }
}
