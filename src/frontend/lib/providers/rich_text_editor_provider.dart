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
      
      // Clear document and mapping
      _document.clear();
      _nodeToBlockMap.clear();
      
      // Sort blocks by order
      final sortedBlocks = List.from(_blocks)
        ..sort((a, b) => a.order.compareTo(b.order));
      
      _logger.debug('Creating document nodes for ${sortedBlocks.length} blocks');
      // Create node based on block type
      // Keep track of created nodes by block ID to help with selection restoration
      final Map<String, String> blockToNodeMap = {};
      
      // Convert each block to a document node
      for (final block in sortedBlocks) {
        try {
          final nodes = _createNodesFromBlock(block);
          
          // Add all nodes to document
          for (final node in nodes) {
            _document.add(node);
            // Map node ID to block ID
            _nodeToBlockMap[node.id] = block.id;
            
            // Also track the first node for each block
            if (!blockToNodeMap.containsKey(block.id)) {
              blockToNodeMap[block.id] = node.id;
            }
          }
        } catch (e) {
          _logger.error('Error creating node for block ${block.id}: $e');
        }
      }
      
      _logger.debug('Document populated with ${_document.length} nodes');
      
      // Try to restore selection if possible
      if (_document.isNotEmpty) {
        // First, try to find the same node ID in the new document
        String? newNodeId;
        
        if (previousNodeId != null && previousNodeId.isNotEmpty) {
          // Get the block ID that the previous node belonged to
          final previousBlockId = _nodeToBlockMap[previousNodeId];
          
          if (previousBlockId != null) {
            // Look for a node with the same block ID
            newNodeId = blockToNodeMap[previousBlockId];
          }
        }
        
        // If we found a match or otherwise need to reset, do it after a small delay
        // to let the document stabilize
        Future.delayed(Duration.zero, () {
          try {
            // If we have a node to select, use it
            if (newNodeId != null && newNodeId.isNotEmpty) {
              final node = _document.getNodeById(newNodeId);
              if (node != null && node is TextNode) {
                int offset = previousTextOffset ?? 0;
                
                // Ensure offset is within text bounds
                offset = offset.clamp(0, node.text.length);
                
                _composer.setSelectionWithReason(DocumentSelection.collapsed(
                    position: DocumentPosition(
                      nodeId: newNodeId,
                      nodePosition: TextNodePosition(offset: offset),
                    ),
                  ),
                );
              } 
              // If no matching node, just select the first text node
              else if (_document.isNotEmpty) {
                for (final node in _document) {
                  if (node is TextNode) {
                    _composer.setSelectionWithReason(DocumentSelection.collapsed(
                        position: DocumentPosition(
                          nodeId: node.id,
                          nodePosition: const TextNodePosition(offset: 0),
                        ),
                      ),
                    );
                    break;
                  }
                }
              }
            }
          } catch (e) {
            _logger.error('Error restoring selection: $e');
          }
        });
      }
    } catch (e) {
      _logger.error('Error populating document: $e');
    } finally {
      _updatingDocument = false;
    }
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
      
      // Update our blocks list and recreate document
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
    
  @override
  void dispose() {
    _logger.debug('Disposing rich text editor provider');
    _document.removeListener(_documentChangeListener);
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _composer.dispose();
    super.dispose();
  }
}
