import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note.dart';
import '../models/block.dart';
import '../providers/notes_provider.dart';
import '../providers/block_provider.dart';
import '../providers/websocket_provider.dart';
import '../providers/rich_text_editor_provider.dart';
import '../utils/logger.dart';
import '../widgets/rich_text_editor.dart';
import '../core/theme.dart';

class NoteEditorScreen extends StatefulWidget {
  final Note note;
  const NoteEditorScreen({Key? key, required this.note}) : super(key: key);

  @override
  _NoteEditorScreenState createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final Logger _logger = Logger('NoteEditorScreen');
  late TextEditingController _titleController;
  bool _isLoading = true;
  List<Block> _blocks = [];
  bool _ignoreBlockUpdates = false;
  bool _initialized = false;
  
  // Store provider references to use safely in dispose
  late WebSocketProvider _webSocketProvider;
  late NotesProvider _notesProvider;
  late BlockProvider _blockProvider;
  
  // Rich text editor provider
  RichTextEditorProvider? _editorProvider;
  
  // Counter to track updates from provider
  int _updateCounter = 0;
  
  // Set to track blocks that existed at screen initialization
  final Set<String> _initialBlockIds = {};
  
  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);
    
    Timer(Duration.zero, () {
      _initializeProviders();
    });
  }
  
  void _initializeProviders() {
    if (_initialized) return;
    _initialized = true;
    
    // Store provider references directly
    _notesProvider = Provider.of<NotesProvider>(context, listen: false);
    _blockProvider = Provider.of<BlockProvider>(context, listen: false);
    _webSocketProvider = Provider.of<WebSocketProvider>(context, listen: false);
    
    // Simple listener that only updates when the block provider's counter changes
    _blockProvider.addListener(() {
      if (!mounted) return;
      
      // Only update if there's actually a change in the update counter
      if (_blockProvider.updateCount != _updateCounter) {
        _logger.debug('Block provider update detected ($_updateCounter → ${_blockProvider.updateCount})');
        _updateBlocksFromProvider();
      }
    });
    
    // Ensure WebSocket is connected
    _webSocketProvider.ensureConnected().then((_) {
      // Activate the note
      _notesProvider.activateNote(widget.note.id);
      _blockProvider.activateNote(widget.note.id);
      
      // Subscribe to WebSocket events with standardized resource.action patterns
      _webSocketProvider.subscribe('note', id: widget.note.id);
      
      // Enhanced block event subscriptions with standardized event names
      _webSocketProvider.subscribe('block', id: null); // All blocks
      _webSocketProvider.subscribe('note:blocks', id: widget.note.id); // Blocks for this note
      _webSocketProvider.subscribe('block.created'); // Block creation events
      _webSocketProvider.subscribe('block.updated'); // Block update events
      _webSocketProvider.subscribe('block.deleted'); // Block deletion events
      
      // Set up event handlers for real-time block updates
      _setupBlockEventHandlers();
      
      _logger.info('Subscribed to note ${widget.note.id} and its blocks');
    });
    
    // Fetch blocks regardless of WebSocket status
    _fetchBlocks();
    
    _logger.info('Initialized providers for note ${widget.note.id}');
  }

  // Set up handlers for block-related WebSocket events
  void _setupBlockEventHandlers() {
    // Handle block creation events
    _webSocketProvider.on('block.created', (data) {
      _handleBlockCreatedEvent(data);
    });
    
    // Handle block update events
    _webSocketProvider.on('block.updated', (data) {
      _handleBlockUpdatedEvent(data);
    });
    
    // Handle block deletion events
    _webSocketProvider.on('block.deleted', (data) {
      _handleBlockDeletedEvent(data);
    });
  }

  // Handle block creation event from WebSocket
  void _handleBlockCreatedEvent(dynamic data) {
    _logger.info('Received block.created event: $data');
    
    // Extract block ID from the event data
    String? blockId;
    String? noteId;
    
    if (data is Map) {
      blockId = data['id']?.toString();
      noteId = data['noteId']?.toString();
    } else if (data is String) {
      blockId = data;
    }
    
    if (blockId == null) {
      _logger.error('Unable to extract block ID from event data');
      return;
    }
    
    // Check if this block belongs to the current note
    if (noteId != null && noteId != widget.note.id) {
      _logger.debug('Block belongs to note $noteId, not ${widget.note.id}, ignoring');
      return;
    }
    
    // Set a brief delay to ensure backend has processed the block creation
    Future.delayed(const Duration(milliseconds: 300), () {
      _logger.info('Fetching new block $blockId after delay');
      _fetchBlockById(blockId!);
    });
  }

  // Handle block update event from WebSocket
  void _handleBlockUpdatedEvent(dynamic data) {
    _logger.info('Received block.updated event: $data');
    
    // Extract block ID from the event data
    String? blockId;
    if (data is Map && data.containsKey('id')) {
      blockId = data['id'].toString();
    } else if (data is String) {
      blockId = data;
    }
    
    if (blockId == null) {
      _logger.error('Unable to extract block ID from event data');
      return;
    }
    
    // Check if this block is one we're already tracking
    bool isKnownBlock = _blocks.any((block) => block.id == blockId);
    if (isKnownBlock) {
      // Fetch the updated block
      _fetchBlockById(blockId);
    }
  }

  // Handle block deletion event from WebSocket
  void _handleBlockDeletedEvent(dynamic data) {
    _logger.info('Received block.deleted event: $data');
    
    // Extract block ID from the event data
    String? blockId;
    if (data is Map && data.containsKey('id')) {
      blockId = data['id'].toString();
    } else if (data is String) {
      blockId = data;
    }
    
    if (blockId == null) {
      _logger.error('Unable to extract block ID from event data');
      return;
    }
    
    // Check if this block is one we're tracking
    bool removedBlock = false;
    _blocks.removeWhere((block) {
      if (block.id == blockId) {
        removedBlock = true;
        return true;
      }
      return false;
    });
    
    if (removedBlock) {
      // Update the editor with the remaining blocks
      if (_editorProvider != null) {
        _editorProvider!.updateBlocks(_blocks);
      }
      
      if (mounted) {
        setState(() {});
      }
    }
  }

  // Fetch a specific block by ID with improved error handling and logging
  Future<void> _fetchBlockById(String blockId) async {
    try {
      _logger.info('Fetching block with ID: $blockId');
      
      final blockProvider = Provider.of<BlockProvider>(context, listen: false);
      final Block? block = await blockProvider.fetchBlockById(blockId);
      
      if (block != null) {
        _logger.info('Successfully fetched block $blockId of type ${block.type}');
        
        if (block.noteId == widget.note.id) {
          bool isNewBlock = !_blocks.any((b) => b.id == block.id);
          
          if (isNewBlock) {
            _logger.info('Adding new block ${block.id} to the editor');
            // Add the new block to our list
            setState(() {
              _blocks.add(block);
              // Sort blocks by order
              _blocks.sort((a, b) => a.order.compareTo(b.order));
            });
          } else {
            _logger.info('Updating existing block ${block.id}');
            // Update existing block
            setState(() {
              int index = _blocks.indexWhere((b) => b.id == block.id);
              if (index >= 0) {
                _blocks[index] = block;
              }
            });
          }
          
          // Update the editor with the new/updated blocks - force rebuild
          _logger.info('Updating editor with modified block list: ${_blocks.length} blocks');
          if (_editorProvider != null) {
            // Use a timer to ensure state has updated before updating the provider
            Future.microtask(() {
              if (mounted) {
                _editorProvider!.updateBlocks(_blocks);
              }
            });
          } else {
            _logger.info('Creating new editor provider since none exists');
            _createEditorProvider();
          }
        } else {
          _logger.debug('Block belongs to note ${block.noteId}, not ${widget.note.id}');
        }
      } else {
        _logger.error('Failed to fetch block $blockId, returned null');
      }
    } catch (e) {
      _logger.error('Error fetching block $blockId', e);
    }
  }

  // Fetch blocks for this note
  Future<void> _fetchBlocks() async {
    setState(() => _isLoading = true);
    
    try {
      final blockProvider = Provider.of<BlockProvider>(context, listen: false);
      await blockProvider.fetchBlocksForNote(widget.note.id);
      
      // After fetching, get blocks from provider and sort by order
      _updateBlocksFromProvider();
      
      // Store initial block IDs for later comparison
      _initialBlockIds.clear();
      for (final block in _blocks) {
        _initialBlockIds.add(block.id);
      }
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      _logger.error('Error fetching blocks', e);
      setState(() => _isLoading = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load note blocks')),
        );
      }
    }
  }

  // Update blocks from provider
  void _updateBlocksFromProvider() {
    if (_ignoreBlockUpdates) {
      _logger.debug('Ignoring block updates due to local edit');
      return;
    }
    
    final blockProvider = Provider.of<BlockProvider>(context, listen: false);
    final newBlocks = blockProvider.getBlocksForNote(widget.note.id);
    
    // Sort blocks by order
    newBlocks.sort((a, b) => a.order.compareTo(b.order));
    
    // Update our local update counter to match the provider
    _updateCounter = blockProvider.updateCount;
    
    // Check if the blocks have actually changed
    bool needsUpdate = _blocks.length != newBlocks.length;
    
    // If counts are same, check for content changes
    if (!needsUpdate) {
      // Build maps of existing blocks by ID for quick comparison
      final Map<String, Block> existingBlocksMap = {
        for (var block in _blocks) block.id: block
      };
      
      // Check for any changes
      for (final newBlock in newBlocks) {
        final existingBlock = existingBlocksMap[newBlock.id];
        if (existingBlock == null || 
            existingBlock.type != newBlock.type ||
            existingBlock.order != newBlock.order ||
            existingBlock.content.toString() != newBlock.content.toString()) {
          needsUpdate = true;
          break;
        }
      }
    }
    
    if (needsUpdate) {
      _logger.info('Blocks changed, updating editor content');
      
      // Update our blocks list
      _blocks = List.from(newBlocks);
      
      // Update editor provider if it exists
      if (_editorProvider != null) {
        _editorProvider!.updateBlocks(_blocks);
      } else {
        // Create editor provider if it doesn't exist yet
        _createEditorProvider();
      }
      
      // Update UI
      if (mounted) {
        setState(() {});
      }
    }
  }
  
  // Create editor provider with our blocks
  void _createEditorProvider() {
    _logger.info('Creating editor provider with ${_blocks.length} blocks');
    
    // Dispose previous provider if it exists
    if (_editorProvider != null) {
      _logger.debug('Disposing existing editor provider');
      _editorProvider!.dispose();
      _editorProvider = null;
    }
    
    // Create new provider with necessary callbacks
    _editorProvider = RichTextEditorProvider(
      blocks: _blocks,
      onBlockContentChanged: (blockId, content) {
        _updateBlockContent(blockId, content);
      },
      onBlockDeleted: (blockId) {
        _handleBlockDeletion(blockId);
      },
      onFocusLost: () {
        // Save title and all block content when focus is lost
        _saveTitle();
        _saveAllBlockContents();
      },
    );
    
    // Ensure UI is refreshed
    if (mounted) {
      setState(() {});
    }
  }
  
  // Handle block deletion
  void _handleBlockDeletion(String blockId) {
    _logger.info('Handling block deletion for block: $blockId');
    
    _ignoreBlockUpdates = true;
    
    try {
      // Remove block from local list
      setState(() {
        _blocks.removeWhere((block) => block.id == blockId);
      });
      
      // Delete block on the server
      Provider.of<BlockProvider>(context, listen: false).deleteBlock(blockId);
      
    } catch (e) {
      _logger.error('Error deleting block', e);
    } finally {
      // Reset ignore flag after a delay
      Future.delayed(const Duration(milliseconds: 500), () {
        _ignoreBlockUpdates = false;
      });
    }
  }
  
  // Save all block contents to server
  void _saveAllBlockContents() {
    _logger.info('Saving all block contents to server');
    
    // Force editor to commit any pending changes
    if (_editorProvider != null) {
      _editorProvider!.commitAllContent();
    }
    
    // Check for blocks that no longer exist and delete them
    _reconcileBlocksWithServer();
  }

  // Compare current blocks with initial blocks to determine updates/deletes
  void _reconcileBlocksWithServer() {
    _logger.info('Reconciling blocks with server...');
    
    // Current blocks as a map for efficient lookup
    final Map<String, Block> currentBlocksMap = {
      for (var block in _blocks) block.id: block
    };
    
    // Find blocks that were removed
    final List<String> deletedBlockIds = [];
    for (final initialId in _initialBlockIds) {
      if (!currentBlocksMap.containsKey(initialId)) {
        deletedBlockIds.add(initialId);
      }
    }
    
    // Delete blocks that were removed
    if (deletedBlockIds.isNotEmpty) {
      _logger.info('Deleting blocks: ${deletedBlockIds.join(', ')}');
      final blockProvider = Provider.of<BlockProvider>(context, listen: false);
      
      for (final blockId in deletedBlockIds) {
        blockProvider.deleteBlock(blockId);
      }
    }
  }

  // Save note title
  void _saveTitle() {
    if (_titleController.text != widget.note.title) {
      Provider.of<NotesProvider>(context, listen: false)
          .updateNote(widget.note.id, _titleController.text);
    }
  }

  // Update a specific block's content
  void _updateBlockContent(String blockId, dynamic content) {
    // Set flag to prevent external updates from messing with cursor position
    _ignoreBlockUpdates = true;
    
    _logger.info('Updating block $blockId with new content');
    // Update block content on the server immediately
    Provider.of<BlockProvider>(context, listen: false)
        .updateBlockContent(blockId, content);
    
    // Reset the flag after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      _ignoreBlockUpdates = false;
    });
  }

  // Add a new block with better error handling and more explicit UI updates
  Future<void> _addBlock({String type = 'text'}) async {
    try {
      _logger.info('Adding new block of type: $type');
      
      final blockProvider = Provider.of<BlockProvider>(context, listen: false);
      
      // Calculate the highest order value
      int newOrder = 0;
      if (_blocks.isNotEmpty) {
        newOrder = _blocks.map((b) => b.order).reduce((a, b) => a > b ? a : b) + 1;
      }
      
      // Create initial content
      Map<String, dynamic> initialContent;
      
      switch (type) {
        case 'heading':
          initialContent = {'text': 'New heading', 'level': 1};
          break;
        case 'checklist':
          initialContent = {'text': 'New item', 'checked': false};
          break;
        case 'code':
          initialContent = {'text': '', 'language': 'plain'};
          break;
        default:
          initialContent = {'text': ''};
          break;
      }
      
      // Create block
      _logger.debug('Creating block in note ${widget.note.id} with order $newOrder');
      final block = await blockProvider.createBlock(
        widget.note.id,
        initialContent, 
        type,
        newOrder,
      );
      
      // Add block to local state immediately for better UX
      setState(() {
        // Only add if it doesn't already exist
        if (!_blocks.any((b) => b.id == block.id)) {
          _blocks.add(block);
          _blocks.sort((a, b) => a.order.compareTo(b.order));
        }
      });
      
      // Update the UI after a delay to ensure state has updated
      Future.microtask(() {
        if (mounted) {
          // Update the editor with the new block
          if (_editorProvider != null) {
            _logger.debug('Updating editor provider with new block');
            _editorProvider!.updateBlocks(_blocks);
          } else {
            _logger.debug('Creating new editor provider after block addition');
            _createEditorProvider();
          }
        }
      });
      
    } catch (e) {
      _logger.error('Error adding block', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add block')),
        );
      }
    }
  }

  // Save content and sync with server
  void _saveAllContent() {
    _logger.info('Saving all content and syncing with server');
    
    // First save title
    _saveTitle();
    
    // Then commit all block content
    if (_editorProvider != null) {
      // First commit any pending edits in the editor 
      _editorProvider!.commitAllContent();
      
      // Then reconcile with server by comparing current blocks with initial blocks
      _reconcileBlocksWithServer();
    }
  }

  @override
  void dispose() {
    // Safely unsubscribe and clean up using stored provider references
    if (_initialized) {
      try {
        // Deactivate note in providers
        _notesProvider.deactivateNote(widget.note.id);
        _blockProvider.deactivateNote(widget.note.id);
        
        // Unsubscribe from standardized resource.action events
        _webSocketProvider.unsubscribe('note', id: widget.note.id);
        _webSocketProvider.unsubscribe('note:blocks', id: widget.note.id);
        _webSocketProvider.unsubscribe('block.created');
        _webSocketProvider.unsubscribe('block.updated');
        _webSocketProvider.unsubscribe('block.deleted');
      } catch (e) {
        _logger.error('Error during disposal', e);
      }
    }
    
    // Dispose editor provider
    _editorProvider?.dispose();
    
    // Dispose controllers
    _titleController.dispose();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _saveAllContent();
            Navigator.pop(context);
          },
        ),
        title: TextField(
          controller: _titleController,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
          cursorColor: Colors.white, // Add cursor color to make it visible
          cursorWidth: 2.0, // Increase cursor width for visibility
          decoration: const InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hintText: 'Note Title',
            hintStyle: TextStyle(color: Colors.white70),
            contentPadding: EdgeInsets.zero,
            isDense: true,
            filled: false,
          ),
          onChanged: (_) => _saveTitle(),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              _addBlock(type: value);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'text',
                child: Text('Add Text Block'),
              ),
              const PopupMenuItem(
                value: 'heading',
                child: Text('Add Heading Block'),
              ),
              const PopupMenuItem(
                value: 'checklist',
                child: Text('Add Checklist Block'),
              ),
              const PopupMenuItem(
                value: 'code',
                child: Text('Add Code Block'),
              ),
            ],
            icon: const Icon(Icons.add),
            tooltip: 'Add Block',
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              _saveAllContent();
              Navigator.pop(context);
            },
            tooltip: 'Save Note',
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _blocks.isEmpty
              ? _buildEmptyState()
              : _buildEditor(),
    );
  }
  
  // Build the editor widget
  Widget _buildEditor() {
    // Create provider if it doesn't exist
    if (_editorProvider == null) {
      _createEditorProvider();
    }
    
    // Return the editor widget
    return _editorProvider != null
        ? RichTextEditor(provider: _editorProvider!)
        : const Center(child: Text('Error initializing editor'));
  }
  
  // Build the empty state widget
  Widget _buildEmptyState() {
    final theme = Theme.of(context); // Get the theme from context
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.note_add_outlined,
            size: 80,
            color: theme.primaryColor.withOpacity(0.5), // Use theme primary color
          ),
          const SizedBox(height: 24),
          Text(
            'This note is empty',
            style: theme.textTheme.headlineSmall, // Use theme text style
          ),
          const SizedBox(height: 16),
          Text(
            'Add a block to start writing',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color, // Use theme text color
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _addBlock(),
            icon: const Icon(Icons.add),
            label: const Text('Add Text Block'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              // The button will automatically use the theme's primary color
            ),
          ),
        ],
      ),
    );
  }
}
