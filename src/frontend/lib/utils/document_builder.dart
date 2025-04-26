import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart' hide Logger;
import '../models/block.dart';
import '../utils/logger.dart';

/// Class that handles mapping between Blocks and SuperEditor DocumentNodes
class DocumentBuilder {
  final Logger _logger = Logger('SuperEditorDocumentMapper');
  
  // Document components
  late MutableDocument document;
  late MutableDocumentComposer composer;
  late Editor editor;
  late FocusNode focusNode;
  
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
  }
  
  void dispose() {
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
  
  // Convert blocks to document nodes and populate the document
  void populateDocumentFromBlocks(List<Block> blocks) {
    if (_updatingDocument) {
      _logger.debug('Already updating document, skipping');
      return;
    }
    
    _updatingDocument = true;
    _logger.info('Populating document with ${blocks.length} blocks');
    
    try {
      // Remember current selection
      String? previousNodeId;
      int? previousTextOffset;
      DocumentPosition? previousPosition;
      
      if (composer.selection != null) {
        previousNodeId = composer.selection?.extent.nodeId;
        if (composer.selection?.extent.nodePosition is TextNodePosition) {
          previousTextOffset = (composer.selection!.extent.nodePosition as TextNodePosition).offset;
          previousPosition = composer.selection!.extent;
        }
      }
      
      // Clear document and mapping
      document.clear();
      nodeToBlockMap.clear();
      
      // Sort blocks by order
      final sortedBlocks = List.from(blocks)
        ..sort((a, b) => a.order.compareTo(b.order));
      
      _logger.debug('Creating document nodes for ${sortedBlocks.length} blocks');
      // Create node based on block type
      // Keep track of created nodes by block ID to help with selection restoration
      final Map<String, String> blockToNodeMap = {};
      
      // Convert each block to a document node
      for (final block in sortedBlocks) {
        try {
          final nodes = createNodesFromBlock(block);
          
          // Add all nodes to document
          for (final node in nodes) {
            document.add(node);
            // Map node ID to block ID
            nodeToBlockMap[node.id] = block.id;
            
            // Also track the first node for each block
            if (!blockToNodeMap.containsKey(block.id)) {
              blockToNodeMap[block.id] = node.id;
            }
          }
        } catch (e) {
          _logger.error('Error creating node for block ${block.id}: $e');
        }
      }
      
      _logger.debug('Document populated with ${document.length} nodes');
      
      // Try to restore selection if possible
      if (document.isNotEmpty) {
        // First, try to find the same node ID in the new document
        String? newNodeId;
        
        if (previousNodeId != null && previousNodeId.isNotEmpty) {
          // Get the block ID that the previous node belonged to
          final previousBlockId = nodeToBlockMap[previousNodeId];
          
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
              final node = document.getNodeById(newNodeId);
              if (node != null && node is TextNode) {
                int offset = previousTextOffset ?? 0;
                
                // Ensure offset is within text bounds
                offset = offset.clamp(0, node.text.length);
                
                composer.setSelectionWithReason(
                  DocumentSelection.collapsed(
                    position: DocumentPosition(
                      nodeId: newNodeId,
                      nodePosition: TextNodePosition(offset: offset),
                    ),
                  ),
                  SelectionReason.contentChange, // Use contentChange since this is not a user interaction
                );
              } 
              // If no matching node, just select the first text node
              else if (document.isNotEmpty) {
                for (final node in document) {
                  if (node is TextNode) {
                    composer.setSelectionWithReason(
                      DocumentSelection.collapsed(
                        position: DocumentPosition(
                          nodeId: node.id,
                          nodePosition: const TextNodePosition(offset: 0),
                        ),
                      ),
                      SelectionReason.contentChange, // Use contentChange since this is not a user interaction
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
  
  // Calculate a reasonable order value for a new node
  Future<int> calculateOrderForNewNode(String nodeId, List<Block> blocks) async {
    // Get the position of this node in the document
    final nodeIndex = document.getNodeIndexById(nodeId);
    if (nodeIndex == null) return 1000; // Fallback value
    
    // Sort blocks by order to find neighbors
    final sortedBlocks = List.from(blocks)..sort((a, b) => a.order.compareTo(b.order));
    
    // If this is the first node, put it at the beginning
    if (nodeIndex == 0) {
      return sortedBlocks.isEmpty ? 10 : sortedBlocks.first.order - 10;
    }
    
    // If this is the last node, put it at the end
    if (nodeIndex >= document.length - 1) {
      return sortedBlocks.isEmpty ? 10 : sortedBlocks.last.order + 10;
    }
    
    // Otherwise, find the blocks before and after this node
    // and place it between them
    final prevNodeId = document.getNodeAt(nodeIndex - 1)?.id;
    final nextNodeId = document.getNodeAt(nodeIndex + 1)?.id;
    
    int prevOrder = 0;
    int nextOrder = 1000;
    
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
    
    // Calculate an order between the two
    return prevOrder + ((nextOrder - prevOrder) ~/ 2);
  }
  
  // Extract content from a node in the format expected by the API
  Map<String, dynamic> extractContentFromNode(DocumentNode node, String blockId, Block originalBlock) {
    Map<String, dynamic> content = {};
    
    if (node is ParagraphNode) {
      // Basic text content
      content['text'] = node.text.toPlainText();
      
      // Extract spans/formatting information
      final spans = extractSpansFromAttributedText(node.text);
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
      final spans = extractSpansFromAttributedText(node.text);
      if (spans.isNotEmpty) {
        content['spans'] = spans;
      }
    }
    
    return content;
  }
  
  // Creates nodes from a block
  List<DocumentNode> createNodesFromBlock(Block block) {
    final content = block.content;
    
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
        return [
          ParagraphNode(
            id: Editor.createNodeId(),
            text: createAttributedTextFromContent(text, content),
          ),
        ];
    }
  }
  
  // Create AttributedText from content including spans
  AttributedText createAttributedTextFromContent(String text, dynamic content) {
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
  List<Map<String, dynamic>> extractSpansFromAttributedText(AttributedText attributedText) {
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
}
