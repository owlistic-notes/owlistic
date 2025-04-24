import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart' hide Logger;
import '../models/block.dart';
import '../utils/logger.dart';

/// Provider for managing the state of a full-page rich text editor that combines multiple blocks
class RichTextEditorProvider with ChangeNotifier {
  final Logger _logger = Logger('RichTextEditorProvider');
  
  // Document components
  late MutableDocument _document;
  late MutableDocumentComposer _composer;
  late Editor _editor;
  late FocusNode _focusNode;
  
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

  // Get the mapping between document node IDs and block IDs
  getNodeToBlockMapping() {
    return _nodeToBlockMap;
  }
  
  // The blocks used to create the document
  List<Block> _blocks = [];
  
  // Mapping between document node IDs and block IDs
  final Map<String, String> _nodeToBlockMap = {};
  
  // Content update debouncer
  DateTime _lastEdit = DateTime.now();
  String? _currentEditingBlockId;
  
  // Flag to prevent recursive document updates
  bool _updatingDocument = false;
  
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
  
  // Standard constructor with callback parameters
  RichTextEditorProvider({
    required List<Block> blocks,
    this.onBlockContentChanged,
    this.onMultiBlockOperation,
    this.onBlockDeleted,
    this.onBlocksMerged,
    this.onFocusLost,
  }) {
    _blocks = List.from(blocks);
    // Store original blocks for later comparison
    _originalBlocks.addAll(blocks); 
    _initialize();
  }
  
  // Getters
  MutableDocument get document => _document;
  DocumentComposer get composer => _composer;
  Editor get editor => _editor;
  FocusNode get focusNode => _focusNode;
  List<Block> get blocks => List.unmodifiable(_blocks);
  
  // Standardized activate/deactivate methods
  void activate() {
    _isActive = true;
    _logger.info('RichTextEditorProvider activated');
  }

  void deactivate() {
    _isActive = false;
    _logger.info('RichTextEditorProvider deactivated');
    
    // Commit all content before deactivating
    commitAllContent();
  }
  
  // Add resetState for consistency
  void resetState() {
    _logger.info('Resetting RichTextEditorProvider state');
    // Clear document
    _document.clear();
    _nodeToBlockMap.clear();
    _blocks.clear();
    _originalBlocks.clear();
    _isActive = false;
    notifyListeners();
  }
  
  void _initialize() {
    // Create an empty document first
    _document = MutableDocument();
    
    // Create composer
    _composer = MutableDocumentComposer();
    
    _editor = createDefaultDocumentEditor(document: _document, composer: _composer);
    
    // Create focus node
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
    
    // Listen for document changes
    _document.addListener(_documentChangeListener);
    
    // Add blocks to document
    _populateDocumentFromBlocks();
    
    _logger.info('Rich text editor initialized with ${_blocks.length} blocks');
  }
 
  // Convert blocks to document nodes
  void _populateDocumentFromBlocks() {
    if (_updatingDocument) {
      _logger.debug('Already updating document, skipping');
      return;
    }
    
    _updatingDocument = true;
    _logger.info('Populating document with ${_blocks.length} blocks');
    
    try {
      // Remember current selection
      String? previousNodeId;
      int? previousTextOffset;
      DocumentPosition? previousPosition;
      
      if (_composer.selection != null) {
        previousNodeId = _composer.selection?.extent.nodeId;
        if (_composer.selection?.extent.nodePosition is TextNodePosition) {
          previousTextOffset = (_composer.selection!.extent.nodePosition as TextNodePosition).offset;
          previousPosition = _composer.selection!.extent;
        }
      }
      
      // Check if we need to optimize the update instead of rebuilding
      if (_document.isEmpty || _blocks.isEmpty) {
        // Document is empty or we're clearing it - just build from scratch
        _rebuildEntireDocument();
      } else {
        // Use optimized update that preserves structure when possible
        _updateDocumentFromBlocks(previousNodeId, previousTextOffset);
      }

      _logger.debug('Document populated with ${_document.length} nodes');
    } catch (e) {
      _logger.error('Error populating document: $e');
    } finally {
      _updatingDocument = false;
    }
  }

  // Completely rebuild the document from scratch
  void _rebuildEntireDocument() {
    _logger.info('Rebuilding entire document from scratch');
    
    // Clear document and mapping
    _document.clear();
    _nodeToBlockMap.clear();
    
    // Sort blocks by order
    final sortedBlocks = List.from(_blocks)
      ..sort((a, b) => a.order.compareTo(b.order));
    
    _logger.debug('Creating document nodes for ${sortedBlocks.length} blocks');
    
    // Convert each block to a document node
    for (final block in sortedBlocks) {
      try {
        final nodes = _createNodesFromBlock(block);
        
        // Add all nodes to document
        for (final node in nodes) {
          _document.add(node);
          // Map node ID to block ID
          _nodeToBlockMap[node.id] = block.id;
        }
      } catch (e) {
        _logger.error('Error creating node for block ${block.id}: $e');
      }
    }
    
    // Attempt to restore reasonable selection if document not empty
    _attemptToRestoreSelection();
  }
  
  // Optimized update that performs targeted document changes
  void _updateDocumentFromBlocks(String? previousNodeId, int? previousTextOffset) {
    _logger.info('Performing optimized document update');
    
    // Create maps for faster lookups
    final Map<String, Block> currentBlocksMap = {
      for (var b in _blocks) b.id: b
    };
    
    // Get existing nodeIds and their block mappings
    final Map<String, String> existingNodeBlockMap = Map.from(_nodeToBlockMap);
    final Map<String, String> blockToNodeMap = {};
    
    // Reverse map from block ID to node ID (first node for each block)
    existingNodeBlockMap.forEach((nodeId, blockId) {
      if (!blockToNodeMap.containsKey(blockId)) {
        blockToNodeMap[blockId] = nodeId;
      }
    });
    
    // Sort blocks by order
    final sortedBlocks = List.from(_blocks)
      ..sort((a, b) => a.order.compareTo(b.order));
    
    // Track nodes we've processed to identify deleted nodes later
    final Set<String> processedNodes = {};
    
    // Track blocks we need to completely replace due to type changes
    final Set<String> blocksToReplace = {};
    
    // STEP 1: Update existing nodes and identify blocks that need replacing
    for (int i = 0; i < sortedBlocks.length; i++) {
      final block = sortedBlocks[i];
      final existingNodeId = blockToNodeMap[block.id];
      
      if (existingNodeId != null) {
        final existingNode = _document.getNodeById(existingNodeId);
        if (existingNode != null) {
          // Check if type has changed (requiring replacement)
          bool typeChanged = false;
          
          if (existingNode is ParagraphNode && block.type != 'text' && 
              block.type != 'heading' && block.type != 'code') {
            typeChanged = true;
          } else if (existingNode is ListItemNode && block.type != 'checklist') {
            typeChanged = true;
          }
          
          if (typeChanged) {
            blocksToReplace.add(block.id);
            continue;
          }
          
          // Update content of existing node if type hasn't changed
          _updateNodeContentFromBlock(existingNode, block);
          processedNodes.add(existingNodeId);
        }
      }
    }
    
    // STEP 2: Handle node deletions for blocks no longer present
    List<String> nodeIdsToDelete = [];
    existingNodeBlockMap.forEach((nodeId, blockId) {
      if (!currentBlocksMap.containsKey(blockId) || 
          blocksToReplace.contains(blockId)) {
        nodeIdsToDelete.add(nodeId);
      }
    });
    
    // Delete nodes in reverse order to maintain indexes
    nodeIdsToDelete.sort((a, b) {
      final nodeA = _document.getNodeIndexById(a) ?? 0;
      final nodeB = _document.getNodeIndexById(b) ?? 0;
      return nodeB.compareTo(nodeA); // Reverse order
    });
    
    for (final nodeId in nodeIdsToDelete) {
      _logger.debug('Deleting node $nodeId from document');
      final index = _document.getNodeIndexById(nodeId);
      if (index != null) {
        _document.deleteNodeAt(index);
      }
      _nodeToBlockMap.remove(nodeId);
    }
    
    // STEP 3: Insert new blocks and replace blocks with type changes
    for (int i = 0; i < sortedBlocks.length; i++) {
      final block = sortedBlocks[i];
      final existingNodeId = blockToNodeMap[block.id];
      
      final bool isNewBlock = existingNodeId == null;
      final bool needsReplacement = blocksToReplace.contains(block.id);
      
      if (isNewBlock || needsReplacement) {
        // Determine insert position
        int insertIndex;
        
        if (i == 0) {
          insertIndex = 0; // Insert at start
        } else {
          // Try to find the node for the previous block
          int prevIndex = i - 1;
          String? prevNodeId;
          
          while (prevIndex >= 0 && prevNodeId == null) {
            final prevBlockId = sortedBlocks[prevIndex].id;
            prevNodeId = blockToNodeMap[prevBlockId];
            prevIndex--;
          }
          
          if (prevNodeId != null) {
            final prevIndex = _document.getNodeIndexById(prevNodeId);
            insertIndex = prevIndex != null ? prevIndex + 1 : _document.length;
          } else {
            insertIndex = 0; // Fall back to beginning if prev not found
          }
        }
        
        // Clamp to document bounds
        insertIndex = insertIndex.clamp(0, _document.length);
        
        // Create and insert new nodes
        final nodes = _createNodesFromBlock(block);
        for (final node in nodes) {
          if (insertIndex >= _document.length) {
            _document.add(node);
          } else {
            _document.insertNodeAt(insertIndex, node);
          }
          _nodeToBlockMap[node.id] = block.id;
          blockToNodeMap[block.id] = node.id; // Update for subsequent insertions
          insertIndex++; // Move insertion point for next node
        }
        
        _logger.debug('${isNewBlock ? "Inserted" : "Replaced"} block ${block.id} at position $insertIndex');
      }
    }
    
    // STEP 4: Reorder nodes to match block order if needed
    _reorderNodesIfNeeded(sortedBlocks.cast<Block>(), blockToNodeMap);
    
    // Try to restore selection to same position
    _restoreSelection(previousNodeId, previousTextOffset, blockToNodeMap);
  }
  
  // Update content of an existing node from a block
  void _updateNodeContentFromBlock(DocumentNode node, Block block) {
    if (node is ParagraphNode) {
      final content = block.content;
      final text = content is Map ? (content['text']?.toString() ?? '') : (content is String ? content : '');
      
      // Only update if content has changed
      if (node.text.toPlainText() != text) {
        // Create new attributed text
        final attributedText = _createAttributedTextFromContent(text, content);
        
        // Replace the node with a copy that has the new text
        // (ParagraphNode is immutable so we can't modify it directly)
        _document.replaceNodeById(
          node.id,
          node.copyParagraphWith(
            text: attributedText,
            // Preserve existing metadata
            metadata: Map<String, dynamic>.from(node.metadata),
          ),
        );
        
        _logger.debug('Updated content for node ${node.id} (block ${block.id})');
      }
    } else if (node is ListItemNode && block.type == 'checklist') {
      final content = block.content;
      final text = content is Map ? (content['text']?.toString() ?? '') : (content is String ? content : '');
      final checked = content is Map ? (content['checked'] == true) : false;
      final newType = checked ? ListItemType.ordered : ListItemType.unordered;
      
      // Only update if content has changed
      bool needsUpdate = node.text.toPlainText() != text || node.type != newType;
      
      if (needsUpdate) {
        // ListItemNode is also immutable, so create a new one with updated properties
        final attributedText = _createAttributedTextFromContent(text, content);
        
        // Create a new node with the updated properties
        final updatedNode = ListItemNode(
          id: node.id,
          text: attributedText, 
          itemType: newType,
        );
        
        // Replace the node in the document
        _document.replaceNodeById(node.id, updatedNode);
        
        _logger.debug('Updated list item node ${node.id} (block ${block.id})');
      }
    }
  }
  
  // Reorder nodes in the document to match block order if needed
  void _reorderNodesIfNeeded(List<Block> sortedBlocks, Map<String, String> blockToNodeMap) {
    // This is a simplified approach - for complex reordering cases,
    // we might need a more sophisticated algorithm
    
    // Create expected node order
    final List<String> expectedNodeOrder = [];
    for (final block in sortedBlocks) {
      final nodeId = blockToNodeMap[block.id];
      if (nodeId != null) {
        expectedNodeOrder.add(nodeId);
      }
    }
    
    // Check current order
    final List<String> currentNodeOrder = [];
    for (final node in _document) {
      currentNodeOrder.add(node.id);
    }
    
    // Compare orders
    bool orderingNeeded = false;
    if (expectedNodeOrder.length == currentNodeOrder.length) {
      for (int i = 0; i < expectedNodeOrder.length; i++) {
        if (expectedNodeOrder[i] != currentNodeOrder[i]) {
          orderingNeeded = true;
          break;
        }
      }
    } else {
      // Different lengths means ordering needed
      orderingNeeded = true;
    }
    
    if (orderingNeeded) {
      _logger.debug('Reordering nodes to match block order');
      
      // For each node that's out of order, move it to the correct position
      for (int targetIndex = 0; targetIndex < expectedNodeOrder.length; targetIndex++) {
        final expectedNodeId = expectedNodeOrder[targetIndex];
        final currentIndex = _document.getNodeIndexById(expectedNodeId);
        
        if (currentIndex != null && currentIndex != targetIndex) {
          _document.moveNode(nodeId: expectedNodeId, targetIndex: targetIndex);
          _logger.debug('Moved node $expectedNodeId from position $currentIndex to $targetIndex');
        }
      }
    }
  }
  
  // Helper method to try to restore selection after document updates
  void _restoreSelection(String? previousNodeId, int? previousTextOffset, Map<String, String> blockToNodeMap) {
    if (previousNodeId == null || _document.isEmpty) return;
    
    Future.delayed(Duration.zero, () {
      try {
        // First try to find the exact same node
        DocumentNode? targetNode = _document.getNodeById(previousNodeId);
        
        // If node doesn't exist anymore, find its block and the new node for that block
        if (targetNode == null) {
          final previousBlockId = _nodeToBlockMap[previousNodeId];
          if (previousBlockId != null) {
            final newNodeId = blockToNodeMap[previousBlockId];
            if (newNodeId != null) {
              targetNode = _document.getNodeById(newNodeId);
            }
          }
        }
        
        // If we have a target node, set selection
        if (targetNode != null && targetNode is TextNode) {
          int offset = previousTextOffset ?? 0;
          
          // Ensure offset is within text bounds
          offset = offset.clamp(0, targetNode.text.length);
          
          _composer.setSelectionWithReason(DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: targetNode.id,
              nodePosition: TextNodePosition(offset: offset),
            ),
          ));
        } 
        // Fall back to first text node if target not found
        else if (_document.isNotEmpty) {
          _attemptToRestoreSelection();
        }
      } catch (e) {
        _logger.error('Error restoring selection: $e');
      }
    });
  }
  
  // Fallback method to select first text node when specific selection can't be restored
  void _attemptToRestoreSelection() {
    if (_document.isEmpty) return;
    
    Future.delayed(Duration.zero, () {
      for (final node in _document) {
        if (node is TextNode) {
          _composer.setSelectionWithReason(DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: node.id,
              nodePosition: const TextNodePosition(offset: 0),
            ),
          ));
          break;
        }
      }
    });
  }
  
  // DocumentChangeListener implementation
  void _documentChangeListener(_) {
    if (!_updatingDocument) {
      _handleDocumentChange();
    }
  }
  
  // Track which block is being edited and schedule updates
  void _handleDocumentChange() {
    // Get the node that's currently being edited
    final selection = _composer.selection;
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
    final blockId = _nodeToBlockMap[nodeId];
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
    final blockId = _nodeToBlockMap[nodeId];
    if (blockId == null) return;
    
    // Find node in document
    final node = _document.getNodeById(nodeId);
    if (node == null) return;
    
    // Extract content based on node type
    Map<String, dynamic> content = _extractContentFromNode(node, blockId);
    
    // Send content update
    onBlockContentChanged?.call(blockId, content);
    _currentEditingBlockId = null;
  }
  
  // Delete a block
  void deleteBlock(String blockId) {
    _logger.info('Deleting block: $blockId');
    
    // Find nodes belonging to this block
    final nodesToDelete = <String>[];
    _nodeToBlockMap.forEach((nodeId, mappedBlockId) {
      if (mappedBlockId == blockId) {
        nodesToDelete.add(nodeId);
      }
    });
    
    // Delete each node from the document
    _updatingDocument = true;
    try {
      for (final nodeId in nodesToDelete) {
        final node = _document.getNodeById(nodeId);
        if (node != null) {
          _document.deleteNode(nodeId);
        }
        _nodeToBlockMap.remove(nodeId);
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
  
  // Extract content from different node types
  Map<String, dynamic> _extractContentFromNode(DocumentNode node, String blockId) {
    Map<String, dynamic> content = {};
    
    // Find the original block to preserve metadata
    final originalBlock = _blocks.firstWhere((b) => b.id == blockId);
    
    if (node is ParagraphNode) {
      // Basic text content
      content['text'] = node.text.toPlainText();
      
      // Extract spans/formatting information
      final spans = _extractSpansFromAttributedText(node.text);
      if (spans.isNotEmpty) {
        content['spans'] = spans;
      }
      
      // Preserve block-specific metadata
      if (originalBlock.type == 'heading' && originalBlock.content is Map) {
        content['level'] = (originalBlock.content as Map)['level'] ?? 1;
      } else if (originalBlock.type == 'code' && originalBlock.content is Map) {
        content['language'] = (originalBlock.content as Map)['language'] ?? 'plain';
      }
    } else if (node is ListItemNode) {
      content['text'] = node.text.toPlainText();
      content['checked'] = node.type == ListItemType.ordered;
      
      // Extract spans for list items as well
      final spans = _extractSpansFromAttributedText(node.text);
      if (spans.isNotEmpty) {
        content['spans'] = spans;
      }
    }
    
    return content;
  }
  
  // Creates nodes from a block
  List<DocumentNode> _createNodesFromBlock(Block block) {
    final content = block.content;
    
    // Create node based on block type
    switch (block.type) {
      case 'heading':
        final text = content is Map ? (content['text']?.toString() ?? '') : (content is String ? content : '');
        final level = content is Map ? (content['level'] ?? 1) : 1;
        final levelInt = level is int ? level : int.tryParse(level.toString()) ?? 1;
        
        // Create attributed text with proper styling
        final attributedText = _createAttributedTextFromContent(text, content);
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
            text: _createAttributedTextFromContent(text, content),
            itemType: checked ? ListItemType.ordered : ListItemType.unordered,
          ),
        ];
        
      case 'code':
        final text = content is Map ? (content['text']?.toString() ?? '') : (content is String ? content : '');
        return [
          ParagraphNode(
            id: Editor.createNodeId(),
            text: _createAttributedTextFromContent(text, content),
            metadata: const {'blockType': 'code'},
          ),
        ];
        
      case 'text':
      default:
        final text = content is Map ? (content['text']?.toString() ?? '') : (content is String ? content : '');
        return [
          ParagraphNode(
            id: Editor.createNodeId(),
            text: _createAttributedTextFromContent(text, content),
          ),
        ];
    }
  }
  
  // Create AttributedText from content including spans
  AttributedText _createAttributedTextFromContent(String text, dynamic content) {
    final attributedText = AttributedText(text);
    
    // Process spans if available
    if (content is Map && content.containsKey('spans')) {
      final spans = content['spans'];
      if (spans is List) {
        for (final span in spans) {
          if (span is Map && 
              span.containsKey('start') && 
              span.containsKey('end') && 
              span.containsKey('type')) {
            final start = span['start'] as int;
            final end = span['end'] as int;
            final type = span['type'] as String;
            
            // Apply different attributes based on span type
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
            }
          }
        }
      }
    }
    
    return attributedText;
  }
  
  // Extract spans (formatting information) from AttributedText
  List<Map<String, dynamic>> _extractSpansFromAttributedText(AttributedText attributedText) {
    final List<Map<String, dynamic>> spans = [];
    final text = attributedText.text;
    
    // Get all attribution types
    final attributions = [
      const NamedAttribution('bold'),
      const NamedAttribution('italic'),
      const NamedAttribution('underline'),
      const NamedAttribution('strikethrough')
    ];
    
    // Extract spans for each attribution type
    for (final attribution in attributions) {
      final attributionSpans = attributedText.getAttributionSpans({attribution});
      for (final span in attributionSpans) {
        spans.add({
          'start': span.start,
          'end': span.end,
          'type': attribution.id,
        });
      }
    }
    
    // Handle links separately
    for (int i = 0; i < text.length; i++) {
      final attributionsAtPosition = attributedText.getAllAttributionsAt(i);
      for (final attribution in attributionsAtPosition) {
        if (attribution is LinkAttribution) {
          int end = i;
          while (end < text.length && 
                attributedText.getAllAttributionsAt(end).contains(attribution)) {
            end++;
          }
          
          spans.add({
            'start': i,
            'end': end,
            'type': 'link',
            'href': attribution.url,
          });
          
          i = end - 1;
          break;
        }
      }
    }
    
    return _mergeAdjacentSpans(spans);
  }
  
  // Helper method to merge adjacent spans of the same type
  List<Map<String, dynamic>> _mergeAdjacentSpans(List<Map<String, dynamic>> spans) {
    if (spans.isEmpty) return [];
    
    spans.sort((a, b) => a['start'].compareTo(b['start']));
    
    final List<Map<String, dynamic>> mergedSpans = [];
    Map<String, dynamic>? currentSpan;
    
    for (final span in spans) {
      if (currentSpan == null) {
        currentSpan = Map<String, dynamic>.from(span);
      } else if (currentSpan['end'] >= span['start'] && 
                 currentSpan['type'] == span['type'] &&
                 (span['type'] != 'link' || currentSpan['href'] == span['href'])) {
        currentSpan['end'] = span['end'] > currentSpan['end'] ? span['end'] : currentSpan['end'];
      } else {
        mergedSpans.add(currentSpan);
        currentSpan = Map<String, dynamic>.from(span);
      }
    }
    
    if (currentSpan != null) {
      mergedSpans.add(currentSpan);
    }
    
    return mergedSpans;
  }
  
  // Handle focus changes
  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      // Commit any pending changes
      if (_currentEditingBlockId != null) {
        final nodeIds = _document.map((node) => node.id).toList();
        for (final nodeId in nodeIds) {
          if (_nodeToBlockMap[nodeId] == _currentEditingBlockId) {
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
    for (final entry in _nodeToBlockMap.entries) {
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
  void updateBlocks(List<Block> blocks) {
    _logger.info('Updating blocks: received ${blocks.length}, current ${_blocks.length}');
    
    if (_blocks.isEmpty && blocks.isNotEmpty) {
      _logger.info('First blocks received, updating document');
      _blocks = List.from(blocks);
      _populateDocumentFromBlocks();
      notifyListeners();
      return;
    }
    
    // Use a map for more efficient lookups
    final Map<String, Block> existingBlocksMap = {
      for (var block in _blocks) block.id: block
    };
    
    final Map<String, Block> newBlocksMap = {
      for (var block in blocks) block.id: block
    };
    
    // Check for changes: additions, deletions, or modifications
    bool hasChanges = existingBlocksMap.length != newBlocksMap.length;
    
    if (!hasChanges) {
      for (final block in blocks) {
        final existingBlock = existingBlocksMap[block.id];
        if (existingBlock == null || 
            existingBlock.type != block.type ||
            existingBlock.order != block.order ||
            existingBlock.content.toString() != block.content.toString()) {
          hasChanges = true;
          break;
        }
      }
    }
    
    if (hasChanges) {
      _logger.info('Block list has changes, updating document');
      
      // Keep track of what's changed for better log messages
      int addedCount = 0;
      int modifiedCount = 0;
      int removedCount = 0;
      
      // Find added/modified blocks
      for (final block in blocks) {
        if (!existingBlocksMap.containsKey(block.id)) {
          addedCount++;
        } else if (existingBlocksMap[block.id]!.content.toString() != block.content.toString() ||
                 existingBlocksMap[block.id]!.type != block.type ||
                 existingBlocksMap[block.id]!.order != block.order) {
          modifiedCount++;
        }
      }
      
      // Find removed blocks
      for (final id in existingBlocksMap.keys) {
        if (!newBlocksMap.containsKey(id)) {
          removedCount++;
        }
      }
      
      _logger.debug('Changes detected: +$addedCount ~$modifiedCount -$removedCount');
      
      // Update our blocks list and refresh document with optimized updates
      _blocks = List.from(blocks);
      _populateDocumentFromBlocks();
      
      // Notify listeners after document update
      notifyListeners();
    } else {
      _logger.debug('No substantive changes in blocks, skipping update');
    }
  }
  
  // Force immediate content commit for all blocks
  void commitAllContent() {
    _logger.debug('Committing content for all blocks');
    
    // First, check for deleted blocks (in original but not current)
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
    if (!_focusNode.hasFocus) {
      _logger.debug('Requesting focus for editor');
      _focusNode.requestFocus();
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
    _document.removeListener(_documentChangeListener);
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _composer.dispose();
    super.dispose();
  }
}
