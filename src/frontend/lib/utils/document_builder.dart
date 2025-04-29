import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart' hide Logger;
import '../models/block.dart';
import '../utils/logger.dart';

/// Class that handles mapping between Blocks and SuperEditor DocumentNodes
class DocumentBuilder {
  final Logger _logger = Logger('DocumentBuilder');
  
  // Document components
  late MutableDocument document;
  late MutableDocumentComposer composer;
  late Editor editor;
  late FocusNode focusNode;
  
  // Document layout key for accessing the document layout
  final GlobalKey documentLayoutKey = GlobalKey();
  
  // Mapping between document node IDs and block IDs
  final Map<String, String> nodeToBlockMap = {};
  
  // Track nodes that don't yet have server blocks
  final Map<String, DateTime> uncommittedNodes = {};
  
  // Track last known node count to detect new nodes
  int _lastKnownNodeCount = 0;
  
  // For tracking changes in the document structure
  List<String> _lastKnownNodeIds = [];
  
  // Flag to prevent recursive document updates
  bool _updatingDocument = false;
  
  // Track locally modified blocks with timestamps to optimize server updates
  final Map<String, DateTime> _locallyModifiedBlocks = {};
  
  // Track blocks that were explicitly modified by user (not just by server sync)
  final Set<String> _userModifiedBlockIds = {};
  
  // Track blocks that have been fetched from the server
  final Map<String, Block> _serverFetchedBlocks = {};
  
  // Last known selection data for robust position restoration
  String? _lastKnownNodeId;
  int? _lastKnownOffset;
  DocumentSelection? _lastKnownSelection;
  
  // Get the set of blocks that were explicitly modified by user interaction
  Set<String> get userModifiedBlockIds => Set.from(_userModifiedBlockIds);
  
  DocumentBuilder() {
    _initialize();
  }
  
  void _initialize() {
    // Create an empty document first
    document = MutableDocument();
    
    // Create composer
    composer = MutableDocumentComposer();
    
    editor = createDefaultDocumentEditor(document: document, composer: composer);
    
    // Create focus node
    focusNode = FocusNode();
    
    // Store initial node IDs for tracking structure changes
    _lastKnownNodeIds = document.map((node) => node.id).toList();
    _lastKnownNodeCount = document.length;
    
    // Add selection listener to keep track of last valid position
    composer.addListener(_captureSelectionForRecovery);
  }
  
  // Capture selection data when it changes for recovery purposes
  void _captureSelectionForRecovery() {
    final selection = composer.selection;
    if (selection != null) {
      try {
        _lastKnownSelection = selection;
        _lastKnownNodeId = selection.extent.nodeId;
        if (selection.extent.nodePosition is TextNodePosition) {
          _lastKnownOffset = (selection.extent.nodePosition as TextNodePosition).offset;
        }
      } catch (e) {
        _logger.warning('Error capturing selection state: $e');
      }
    }
  }
  
  void dispose() {
    // Remove selection listener
    composer.removeListener(_captureSelectionForRecovery);
    
    focusNode.dispose();
    composer.dispose();
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
          previousBlockId = nodeToBlockMap[previousNodeId];
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
        nodeToBlockMap.clear();
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
              nodeToBlockMap[node.id] = block.id;
              blockToNodeMap[block.id] = node.id;
              
              // Register this block as from server
              registerServerBlock(block);
              
              // Only mark blocks as modified if explicitly requested
              // This allows us to differentiate between initial load and user edits
              if (markAsModified) {
                _locallyModifiedBlocks[block.id] = DateTime.now();
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
              bool validPosition = false;
              
              if (node is TextNode && previousPosition.nodePosition is TextNodePosition) {
                final textNode = node as TextNode;
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
            final previousBlockId = nodeToBlockMap[previousNodeId];
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
    if (nodeToBlockMap.containsKey(nodeId)) {
      _logger.debug('Node $nodeId already mapped to a block, skipping');
      return false;
    }
    
    // Skip if we're already processing this node
    if (uncommittedNodes.containsKey(nodeId)) {
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
    uncommittedNodes[nodeId] = DateTime.now();
    return true;
  }
  
  // Calculate a fractional index order for a new node using midpoint between adjacent blocks
  Future<double> calculateOrderForNewNode(String nodeId, List<Block> blocks) async {
    // Get the position of this node in the document
    final nodeIndex = document.getNodeIndexById(nodeId);
    if (nodeIndex == null) return 1000.0; // Fallback value
    
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
      final prevBlockId = nodeToBlockMap[prevNodeId];
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
      final nextBlockId = nodeToBlockMap[nextNodeId];
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
    _locallyModifiedBlocks[blockId] = DateTime.now();
    _userModifiedBlockIds.add(blockId);
    _logger.debug('Block $blockId marked as explicitly modified by user');
  }
  
  /// Register a block as being fetched from the server
  /// This helps track which blocks should be considered as "server source of truth"
  void registerServerBlock(Block block) {
    _serverFetchedBlocks[block.id] = block;
    // If this block was previously marked as user-modified but is now
    // being updated from the server with a newer timestamp, remove the user-modified flag
    if (_userModifiedBlockIds.contains(block.id)) {
      final modifiedAt = _locallyModifiedBlocks[block.id];
      if (modifiedAt != null && block.updatedAt.isAfter(modifiedAt)) {
        _userModifiedBlockIds.remove(block.id);
        _locallyModifiedBlocks.remove(block.id);
        _logger.debug('Block ${block.id} user modifications overridden by newer server version');
      }
    }
  }

  /// Check if this block should be updated from the server version
  /// Returns true if the server version is newer than any local changes
  bool shouldUpdateFromServer(String blockId, Block serverBlock) {
    // If no local modifications, always update from server
    if (!_locallyModifiedBlocks.containsKey(blockId)) {
      return true;
    }
    
    // Get local modification time
    final localModTime = _locallyModifiedBlocks[blockId]!;
    
    // Compare with server timestamp - only update if server is newer
    return serverBlock.updatedAt.isAfter(localModTime);
  }
  
  /// Check if we should send a block update to the server
  bool shouldSendBlockUpdate(String blockId, Block serverBlock) {
    // If not modified locally, don't send update
    if (!_locallyModifiedBlocks.containsKey(blockId)) {
      return false;
    }
    
    // If explicitly modified by user, always send update
    if (_userModifiedBlockIds.contains(blockId)) {
      return true;
    }
    
    // Get local modification time
    final localModTime = _locallyModifiedBlocks[blockId]!;
    
    // Compare with server timestamp
    final serverUpdateTime = serverBlock.updatedAt;
    
    // Only update if local changes are newer
    if (localModTime.isAfter(serverUpdateTime)) {
      _logger.debug('Block $blockId has newer local changes (local: $localModTime, server: $serverUpdateTime)');
      return true;
    } else {
      _logger.debug('Block $blockId server version is newer or same, skipping update');
      return false;
    }
  }
  
  // Clear modification tracking after successful update
  void clearModificationTracking(String blockId) {
    _locallyModifiedBlocks.remove(blockId);
    _userModifiedBlockIds.remove(blockId);
  }
  
  // Extract content from a node in the format expected by the API
  Map<String, dynamic> extractContentFromNode(DocumentNode node, String blockId, Block originalBlock) {
    // Initialize with original content to preserve metadata and prevent empty content
    Map<String, dynamic> content = Map<String, dynamic>.from(originalBlock.content);
    
    if (node is ParagraphNode) {
      // Get text content and ensure it's not null
      final plainText = node.text.toPlainText();
      
      // BUGFIX: Always update the text field with current content from editor
      content['text'] = plainText;
      
      // Extract spans/formatting information
      final spans = extractSpansFromAttributedText(node.text);
      // Always include spans field to maintain formatting consistency
      content['spans'] = spans;
      
      // Preserve block-specific metadata
      if (originalBlock.type == 'heading') {
        content['level'] = content['level'] ?? 1;
      } else if (originalBlock.type == 'code') {
        content['language'] = content['language'] ?? 'plain';
      }
    } else if (node is ListItemNode) {
      // Get text content and ensure it's not null
      final plainText = node.text.toPlainText();
      content['text'] = plainText;
      content['checked'] = node.type == ListItemType.ordered;
      
      // Extract spans for list items as well
      final spans = extractSpansFromAttributedText(node.text);
      // Always include spans field to maintain formatting consistency
      content['spans'] = spans;
    }
    
    // Mark this block as modified with current timestamp
    markBlockAsModified(blockId);
    
    return content;
  }

  // Extract spans (formatting information) from AttributedText with better handling
  List<Map<String, dynamic>> extractSpansFromAttributedText(AttributedText attributedText) {
    final List<Map<String, dynamic>> spans = [];
    final text = attributedText.text;
    
    // If text is empty, return empty spans
    if (text.isEmpty) {
      return [];
    }
    
    // Use the same attribution types that SuperEditor uses in defaultStyleBuilder
    final attributions = [
      const NamedAttribution('bold'),
      const NamedAttribution('italic'),
      const NamedAttribution('underline'),
      const NamedAttribution('strikethrough')
    ];
    
    // Extract spans for each standard attribution type
    for (final attribution in attributions) {
      final attributionSpans = attributedText.getAttributionSpans({attribution});
      for (final span in attributionSpans) {
        // Ensure span bounds are valid
        if (span.start >= 0 && span.end <= text.length && span.end > span.start) {
          spans.add({
            'start': span.start,
            'end': span.end,
            'type': attribution.id,
          });
        }
      }
    }
    
    // Handle links separately as they're a different type of attribution
    for (int i = 0; i < text.length; i++) {
      final attributionsAtPosition = attributedText.getAllAttributionsAt(i);
      for (final attribution in attributionsAtPosition) {
        if (attribution is LinkAttribution) {
          int end = i;
          while (end < text.length && 
                attributedText.getAllAttributionsAt(end).contains(attribution)) {
            end++;
          }
          
          // Only add if span bounds are valid
          if (i >= 0 && end <= text.length && end > i) {
            spans.add({
              'start': i,
              'end': end,
              'type': 'link',
              'href': attribution.url,
            });
          }
          
          i = end - 1;
          break;
        }
      }
    }
    
    // Merge adjacent spans of the same type to optimize storage
    return _mergeAdjacentSpans(spans);
  }
  
  // Improved helper method to merge adjacent spans of the same type
  List<Map<String, dynamic>> _mergeAdjacentSpans(List<Map<String, dynamic>> spans) {
    if (spans.isEmpty) return [];
    
    // Sort spans by start position for easier processing
    spans.sort((a, b) => a['start'].compareTo(b['start']));
    
    final List<Map<String, dynamic>> mergedSpans = [];
    Map<String, dynamic>? currentSpan;
    
    for (final span in spans) {
      if (currentSpan == null) {
        currentSpan = Map<String, dynamic>.from(span);
      } else if (currentSpan['end'] >= span['start'] && 
                 currentSpan['type'] == span['type'] &&
                 // For links, only merge if they have the same href
                 (span['type'] != 'link' || currentSpan['href'] == span['href'])) {
        // Merge by extending the end of the current span
        currentSpan['end'] = span['end'] > currentSpan['end'] ? span['end'] : currentSpan['end'];
      } else {
        // Different type or non-adjacent spans, add current and start a new one
        mergedSpans.add(currentSpan);
        currentSpan = Map<String, dynamic>.from(span);
      }
    }
    
    // Add the last span if it exists
    if (currentSpan != null) {
      mergedSpans.add(currentSpan);
    }
    
    return mergedSpans;
  }

  // Creates nodes from a block
  List<DocumentNode> createNodesFromBlock(Block block) {
    final content = block.content;
    final String blockType = block.getBlockType();
    
    // Create node based on block type
    switch (block.type) {
      case 'heading':
        final text = content is Map ? (content['text']?.toString() ?? '') : (content is String ? content : '');
        final level = content is Map ? (content['level'] ?? 1) : 1;
        final levelInt = level is int ? level : int.tryParse(level.toString()) ?? 1;
        
        // Create attributed text with proper styling
        final attributedText = createAttributedTextFromContent(text, content);
        return [
          ParagraphNode(
            id: Editor.createNodeId(),
            text: attributedText,
            metadata: {'blockType': 'heading', 'headingLevel': levelInt},
          ),
        ];
        
      case 'checklist':
        final text = content is Map ? (content['text']?.toString() ?? '') : (content is String ? content : '');
        final checked = content is Map ? (content['checked'] == true) : false;
        return [
          ListItemNode(
            id: Editor.createNodeId(),
            text: createAttributedTextFromContent(text, content),
            itemType: checked ? ListItemType.ordered : ListItemType.unordered,
          ),
        ];
        
      case 'code':
        final text = content is Map ? (content['text']?.toString() ?? '') : (content is String ? content : '');
        return [
          ParagraphNode(
            id: Editor.createNodeId(),
            text: createAttributedTextFromContent(text, content),
            metadata: const {'blockType': 'code'},
          ),
        ];
        
      case 'text':
      default:
        final text = content is Map ? (content['text']?.toString() ?? '') : (content is String ? content : '');
        
        // Get blockType from metadata if available
        Map<String, dynamic>? metadata;
        if (block.metadata != null && block.metadata!.containsKey('blockType')) {
          metadata = {'blockType': block.metadata!['blockType']};
        }
        
        return [
          ParagraphNode(
            id: Editor.createNodeId(),
            text: createAttributedTextFromContent(text, content),
            metadata: metadata,
          ),
        ];
    }
  }
  
  // Create AttributedText from content including spans with better error handling
  AttributedText createAttributedTextFromContent(String text, dynamic content) {
    // Safety check for empty text
    if (text.isEmpty) {
      return AttributedText('');
    }
    
    final attributedText = AttributedText(text);
    
    try {
      // Process spans if available - support both 'spans' and 'inlineStyles' keys
      // to match SuperEditor's handling
      List? spans;
      if (content is Map) {
        if (content.containsKey('spans')) {
          spans = content['spans'] as List?;
        } else if (content.containsKey('inlineStyles')) {
          spans = content['inlineStyles'] as List?;
        }
      }
      
      if (spans != null && spans is List) {
        for (final span in spans) {
          if (span is Map && 
              span.containsKey('start') && 
              span.containsKey('end') && 
              span.containsKey('type')) {
            try {
              final start = span['start'] is int ? span['start'] : int.tryParse(span['start'].toString()) ?? 0;
              final end = span['end'] is int ? span['end'] : int.tryParse(span['end'].toString()) ?? 0;
              final type = span['type'] as String? ?? '';
              
              // Validate span range to avoid errors
              if (start >= 0 && end > start && end <= text.length) {
                // Apply attributions based on the type - following SuperEditor's defaults
                switch (type) {
                  case 'bold':
                    attributedText.addAttribution(
                      const NamedAttribution('bold'), 
                      SpanRange(start, end)
                    );
                    break;
                  case 'italic':
                    attributedText.addAttribution(
                      const NamedAttribution('italic'), 
                      SpanRange(start, end)
                    );
                    break;
                  case 'link':
                    final href = span['href'] as String?;
                    if (href != null) {
                      attributedText.addAttribution(
                        LinkAttribution(href), 
                        SpanRange(start, end)
                      );
                    }
                    break;
                  case 'underline':
                    attributedText.addAttribution(
                      const NamedAttribution('underline'), 
                      SpanRange(start, end)
                    );
                    break;
                  case 'strikethrough':
                    attributedText.addAttribution(
                      const NamedAttribution('strikethrough'), 
                      SpanRange(start, end)
                    );
                    break;
                  // Support for SuperEditor's color attributions could be added here
                  case 'color':
                    if (span.containsKey('color')) {
                      // Would need to parse color from the span data
                      // This is left as a TODO for future implementation
                    }
                    break;
                }
              }
            } catch (e) {
              _logger.warning('Error processing span: $e');
              // Continue with next span
            }
          }
        }
      }
    } catch (e) {
      _logger.error('Error processing text spans: $e');
      // Return plain text if span processing fails
    }
    
    return attributedText;
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
    final Map<String, dynamic> nodeContent = extractContentFromNode(node, blockId, block);
    
    // Compare the extracted content with the block's content
    // This requires a deep comparison, not just toString()
    if (block.content is Map && nodeContent is Map) {
      // Compare important fields like 'text' and 'spans'
      if (block.content['text'] != nodeContent['text']) {
        return true;
      }
      
      // Check if spans have changed (requires deeper comparison)
      final blockSpans = block.content['spans'];
      final nodeSpans = nodeContent['spans'];
      
      if ((blockSpans == null && nodeSpans != null && nodeSpans.isNotEmpty) ||
          (blockSpans != null && blockSpans.isNotEmpty && nodeSpans == null) ||
          (blockSpans != null && nodeSpans != null && 
           blockSpans.toString() != nodeSpans.toString())) {
        return true;
      }
      
      // Check other type-specific fields
      if (block.type == 'heading' && 
          block.content['level'] != nodeContent['level']) {
        return true;
      }
      
      if (block.type == 'checklist' && 
          block.content['checked'] != nodeContent['checked']) {
        return true;
      }
      
      if (block.type == 'code' && 
          block.content['language'] != nodeContent['language']) {
        return true;
      }
      
      return false;
    } else {
      // Fall back to string comparison for simple content
      return block.content.toString() != nodeContent.toString();
    }
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
}
