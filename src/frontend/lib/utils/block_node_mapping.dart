import 'package:owlistic/models/block.dart';
import 'package:owlistic/utils/logger.dart';

/// Represents a mapping between a node in the document and a block in the database
class BlockNodeEntry {
  final String blockId;
  String nodeId;
  DateTime? lastModified;
  bool userModified = false;
  bool uncommitted = false;
  Block? serverData;
  
  BlockNodeEntry(this.blockId, this.nodeId);
}

/// Central class for managing mappings between document nodes and blocks
class BlockNodeMapping {
  final Logger _logger = Logger('BlockNodeMapping');
  
  // Single source of truth for all mappings
  final Map<String, BlockNodeEntry> _blockEntries = {};
  
  // Map of nodeId to blockId for quick lookups
  final Map<String, String> _nodeToBlockMap = {};
  
  // Track nodes that don't yet have server blocks
  final Map<String, DateTime> _uncommittedNodes = {};
  
  /// Returns all block IDs that have been modified by user interaction
  Set<String> get userModifiedBlockIds => 
      _blockEntries.values
          .where((entry) => entry.userModified)
          .map((entry) => entry.blockId)
          .toSet();
  
  /// Returns a map of node IDs to block IDs
  Map<String, String> get nodeToBlockMap => Map.unmodifiable(_nodeToBlockMap);
  
  /// Returns the uncommitted nodes map
  Map<String, DateTime> get uncommittedNodes => Map.unmodifiable(_uncommittedNodes);
  
  /// Link a node to a block
  void linkNodeToBlock(String nodeId, String blockId) {
    // Remove any existing mapping for this node
    removeNodeMapping(nodeId);
    
    // Create or update entry
    if (_blockEntries.containsKey(blockId)) {
      _blockEntries[blockId]!.nodeId = nodeId;
    } else {
      _blockEntries[blockId] = BlockNodeEntry(blockId, nodeId);
    }
    
    // Update reverse lookup map
    _nodeToBlockMap[nodeId] = blockId;
    
    _logger.debug('Linked node $nodeId to block $blockId');
  }
  
  /// Get block ID for a node
  String? getBlockIdForNode(String nodeId) => _nodeToBlockMap[nodeId];
  
  /// Get node ID for a block
  String? getNodeIdForBlock(String blockId) {
    final entry = _blockEntries[blockId];
    return entry?.nodeId;
  }
  
  /// Remove a node mapping
  void removeNodeMapping(String nodeId) {
    final blockId = _nodeToBlockMap[nodeId];
    if (blockId != null) {
      if (_blockEntries.containsKey(blockId) && 
          _blockEntries[blockId]?.nodeId == nodeId) {
        _blockEntries[blockId]!.nodeId = '';
      }
      _nodeToBlockMap.remove(nodeId);
    }
  }
  
  /// Remove a block mapping and its associated node
  void removeBlockMapping(String blockId) {
    final entry = _blockEntries[blockId];
    if (entry != null && entry.nodeId.isNotEmpty) {
      _nodeToBlockMap.remove(entry.nodeId);
    }
    _blockEntries.remove(blockId);
  }
  
  /// Clear all mappings
  void clearMappings() {
    _blockEntries.clear();
    _nodeToBlockMap.clear();
    _uncommittedNodes.clear();
  }
  
  /// Mark a block as modified by user interaction
  void markBlockAsModified(String blockId) {
    if (_blockEntries.containsKey(blockId)) {
      _blockEntries[blockId]!.lastModified = DateTime.now();
      _blockEntries[blockId]!.userModified = true;
    } else {
      // Create on the fly if needed
      final entry = BlockNodeEntry(blockId, '');
      entry.lastModified = DateTime.now();
      entry.userModified = true;
      _blockEntries[blockId] = entry;
    }   
    _logger.debug('Block $blockId marked as modified by user');
  }
  
  /// Clear modification tracking for a block
  void clearModificationTracking(String blockId) {
    if (_blockEntries.containsKey(blockId)) {
      _blockEntries[blockId]!.userModified = false;
    }
  }
  
  /// Mark a node as uncommitted (waiting for server block)
  void markNodeAsUncommitted(String nodeId) {
    _uncommittedNodes[nodeId] = DateTime.now();
  }
  
  /// Remove a node from uncommitted nodes list
  void removeUncommittedNode(String nodeId) {
    _uncommittedNodes.remove(nodeId);
  }
  
  /// Check if a node is uncommitted
  bool isNodeUncommitted(String nodeId) => _uncommittedNodes.containsKey(nodeId);
  
  /// Register a server block, updating our mapping data
  void registerServerBlock(Block block, String nodeId) {
    if (!_blockEntries.containsKey(block.id)) {
      _blockEntries[block.id] = BlockNodeEntry(block.id, nodeId);
    }
    
    final entry = _blockEntries[block.id]!;
    
    // Update node ID if provided
    if (nodeId.isNotEmpty) {
      entry.nodeId = nodeId;
      _nodeToBlockMap[nodeId] = block.id;
    }
    
    // Save server data
    entry.serverData = block;
    
    // Check if this is newer than local modifications
    if (entry.userModified && entry.lastModified != null) {
      if (block.updatedAt.isAfter(entry.lastModified!)) {
        // Server version is newer, clear user modified flag
        entry.userModified = false;
        _logger.debug('Block ${block.id} user modifications overridden by newer server version');
      }
    }
  }
  
  /// Check if a block has been modified by the user
  bool isBlockModifiedByUser(String blockId) {
    return _blockEntries.containsKey(blockId) && 
           _blockEntries[blockId]!.userModified;
  }
  
  /// Check if a block should be updated from server version
  bool shouldUpdateFromServer(String blockId, Block serverBlock) {
    // If no local modifications, always update from server
    if (!_blockEntries.containsKey(blockId) || !_blockEntries[blockId]!.userModified) {
      return true;
    }
    
    // Get local modification time
    final localModTime = _blockEntries[blockId]!.lastModified;
    if (localModTime == null) return true;
    
    // Compare with server timestamp - only update if server is newer
    return serverBlock.updatedAt.isAfter(localModTime);
  }
}