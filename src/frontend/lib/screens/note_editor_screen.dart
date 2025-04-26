import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:thinkstack/utils/websocket_message_parser.dart';
import '../models/note.dart';
import '../models/block.dart';
import '../providers/notes_provider.dart';
import '../providers/block_provider.dart';
import '../providers/websocket_provider.dart';
import '../providers/rich_text_editor_provider.dart';
import '../utils/logger.dart';
import '../widgets/rich_text_editor.dart';
import '../core/theme.dart';
import '../widgets/app_bar_common.dart';

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
  
  // Add scroll controller to detect when to load more blocks
  final ScrollController _scrollController = ScrollController();
  
  // Store loading state for pagination
  bool _loadingMoreBlocks = false;
  
  // Define batch size for initial and subsequent loads
  static const int _initialPageSize = 20;
  static const int _batchSize = 10;
  
  // Current page number for pagination
  int _currentPage = 1;
  
  // Add debounce timer for scroll events
  Timer? _scrollDebouncer;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);
    
    // Add scroll listener to load more blocks when nearing the end
    _scrollController.addListener(_scrollListener);
    
    Timer(Duration.zero, () {
      _initializeProviders();
    });
  }
  
  // Scroll listener to detect when we need to load more blocks
  void _scrollListener() {
    // Don't do anything if we're already loading or have a pending request
    if (_loadingMoreBlocks || _scrollDebouncer?.isActive == true) return;

    // Only trigger near the bottom of the scroll area
    if (_scrollController.position.pixels > 
        _scrollController.position.maxScrollExtent - 500) {
      
      // Debounce scroll events to prevent multiple rapid calls
      _scrollDebouncer?.cancel();
      _scrollDebouncer = Timer(const Duration(milliseconds: 150), () {
        // Check if there are more blocks to load before attempting
        final blockProvider = Provider.of<BlockProvider>(context, listen: false);
        if (blockProvider.hasMoreBlocks(widget.note.id)) {
          _logger.info('Triggered load of page ${_currentPage + 1} from scroll');
          _loadMoreBlocks();
        } else {
          _logger.debug('No more blocks available to load');
        }
      });
    }
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
    if (data == null) {
      _logger.warning('Received null data for block.created event');
      return;
    }
    
    _logger.info('Received block.created event: $data');
    
    try {
      // Use the structured parser to extract data
      final parsedMessage = WebSocketMessage.fromJson(data);
      final String? blockId = WebSocketModelExtractor.extractBlockId(parsedMessage);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
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
        _fetchBlockById(blockId);
      });
    } catch (e) {
      _logger.error('Error handling block create event: $e');
    }
  }

  // Handle block update event from WebSocket
  void _handleBlockUpdatedEvent(dynamic data) {
    if (data == null) {
      _logger.warning('Received null data for block.updated event');
      return;
    }
    
    _logger.info('Received block.updated event: $data');
    
    try {
      // Use the structured parser to extract data
      final parsedMessage = WebSocketMessage.fromJson(data);
      final String? blockId = WebSocketModelExtractor.extractBlockId(parsedMessage);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      if (blockId == null) {
        _logger.error('Unable to extract block ID from event data');
        return;
      }
      
      // Check if this block belongs to the current note
      if (noteId != null && noteId != widget.note.id) {
        _logger.debug('Block belongs to note $noteId, not ${widget.note.id}, ignoring');
        return;
      }
      
      // Check if this block is one we're already tracking
      bool isKnownBlock = _blocks.any((block) => block.id == blockId);
      if (isKnownBlock) {
        // Fetch the updated block
        _fetchBlockById(blockId);
      }
    } catch (e) {
      _logger.error('Error handling block update event: $e');
    }
  }

  // Handle block deletion event from WebSocket
  void _handleBlockDeletedEvent(dynamic data) {
    if (data == null) {
      _logger.warning('Received null data for block.deleted event');
      return;
    }
    
    _logger.info('Received block.deleted event: $data');
    
    try {
      // Use the structured parser to extract data
      final parsedMessage = WebSocketMessage.fromJson(data);
      final String? blockId = WebSocketModelExtractor.extractBlockId(parsedMessage);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      if (blockId == null) {
        _logger.error('Unable to extract block ID from event data');
        return;
      }
      
      // Check if this block belongs to the current note
      if (noteId != null && noteId != widget.note.id) {
        _logger.debug('Block belongs to note $noteId, not ${widget.note.id}, ignoring');
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
    } catch (e) {
      _logger.error('Error handling block delete event: $e');
    }
  }

  // Fetch a specific block by ID with improved error handling and rendering
  Future<void> _fetchBlockById(String blockId) async {
    // Don't fetch if we're already ignoring updates (prevents recursive updates)
    if (_ignoreBlockUpdates) {
      _logger.debug('Ignoring fetch request during local edit for block: $blockId');
      return;
    }
    
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
          
          // FIX: Ensure we update the editor immediately
          // Use a more reliable approach to ensure UI updates
          Future.microtask(() {
            if (mounted) {
              _logger.info('Updating editor with modified block list: ${_blocks.length} blocks');
              
              if (_editorProvider != null) {
                _editorProvider!.updateBlocks(_blocks);
              } else {
                _logger.info('Creating new editor provider since none exists');
                _createEditorProvider();
              }
              
              // Force UI refresh to ensure blocks are visible
              setState(() {});
            }
          });
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

  // Fetch first batch of blocks for this note
  Future<void> _fetchBlocks() async {
    setState(() => _isLoading = true);
    
    try {
      final blockProvider = Provider.of<BlockProvider>(context, listen: false);
      
      // Only fetch initial small batch for quick display
      await blockProvider.fetchBlocksForNote(widget.note.id, 
        page: 1, 
        pageSize: _initialPageSize
      );
      
      // After fetching, get blocks from provider
      _updateBlocksFromProvider();
      
      // Store initial block IDs for later comparison
      _initialBlockIds.clear();
      for (final block in _blocks) {
        _initialBlockIds.add(block.id);
      }
      
      setState(() {
        _isLoading = false;
        _currentPage = 1;
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
  
  // Load more blocks when scrolling
  Future<void> _loadMoreBlocks() async {
    // Safety check - if we're already loading, don't start another request
    if (_loadingMoreBlocks) {
      _logger.debug('Already loading blocks, ignoring request');
      return;
    }
    
    // Set loading flag immediately to prevent multiple calls
    _loadingMoreBlocks = true;
    if (mounted) setState(() {});
    
    try {
      final blockProvider = Provider.of<BlockProvider>(context, listen: false);
      
      // Double check if there are more blocks to load
      if (!blockProvider.hasMoreBlocks(widget.note.id)) {
        _logger.debug('No more blocks to load, cancelling request');
        setState(() {
          _loadingMoreBlocks = false;
        });
        return;
      }
      
      // Log clear info about which page we're loading
      final nextPage = _currentPage + 1;
      _logger.info('Loading blocks page $nextPage of size $_batchSize');
      
      // Capture current scroll position
      final scrollPosition = _scrollController.position.pixels;
      
      // Capture current selection/focus state 
      final editorHasFocus = _editorProvider?.focusNode.hasFocus ?? false;
      final currentSelection = _editorProvider?.composer.selection;
      
      // Load next page of blocks - notice we're using nextPage variable 
      // and only incrementing _currentPage after successful load
      await blockProvider.fetchBlocksForNote(widget.note.id,
        page: nextPage,
        pageSize: _batchSize,
        append: true
      );
      
      // Only update current page after successful fetch
      _currentPage = nextPage;
      
      // Update blocks without disrupting the UI
      _updateBlocksFromProvider(preserveFocus: editorHasFocus);
      
      if (mounted) {
        setState(() {
          _loadingMoreBlocks = false;
        });
        
        // Restore focus if needed
        if (editorHasFocus && currentSelection != null && _editorProvider != null) {
          Future.microtask(() {
            _editorProvider!.restoreFocus(currentSelection);
          });
        }
        
        // Restore scroll position with a slight delay to ensure render is complete
        Future.delayed(const Duration(milliseconds: 50), () {
          if (_scrollController.hasClients && 
              scrollPosition <= _scrollController.position.maxScrollExtent) {
            _scrollController.jumpTo(scrollPosition);
          }
        });
      }
    } catch (e) {
      _logger.error('Error loading more blocks', e);
      if (mounted) {
        setState(() {
          _loadingMoreBlocks = false;
        });
      }
    }
  }

  // Update blocks from provider with focus preservation
  void _updateBlocksFromProvider({bool preserveFocus = false}) {
    if (_ignoreBlockUpdates) {
      _logger.debug('Ignoring block updates due to local edit');
      return;
    }
    
    // Capture current editor state if preserving focus
    final hadFocus = preserveFocus ? _editorProvider?.focusNode.hasFocus ?? false : false;
    final selection = preserveFocus ? _editorProvider?.composer.selection : null;
    
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
        _editorProvider!.updateBlocks(_blocks, preserveFocus: preserveFocus, savedSelection: selection);
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
      noteId: widget.note.id,  // Pass the note ID for block creation
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
      blockProvider: Provider.of<BlockProvider>(context, listen: false), // Pass block provider
    );
    
    // Activate the editor provider
    _editorProvider!.activate();
    
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
      _logger.info('Deleted block: $blockId');
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

  // Update a specific block's content with optimized server sync
  void _updateBlockContent(String blockId, dynamic content) {
    // Set flag to prevent external updates from messing with cursor position
    _ignoreBlockUpdates = true;
    
    _logger.debug('Updating block $blockId with new content');
    
    // Find original block to preserve metadata and pass any needed fields
    final blockIndex = _blocks.indexWhere((block) => block.id == blockId);
    if (blockIndex < 0) {
      _logger.warning('Tried to update non-existent block: $blockId');
      _ignoreBlockUpdates = false;
      return;
    }
    
    final block = _blocks[blockIndex];
    final int order = blockIndex + 1;
    
    // Only send the actual change to the server, not the entire block list
    Provider.of<BlockProvider>(context, listen: false)
        .updateBlockContent(blockId, content, order: order, updateLocalOnly: true);
    
    // Also update our local block content immediately for better responsiveness
    setState(() {
      if (content is Map) {
        // For map content, we need to update the content field
        // Cast the map to Map<String, dynamic> to satisfy type requirements
        _blocks[blockIndex] = block.copyWith(
          content: Map<String, dynamic>.from(content),
          order: order
        );
      } else if (content is String) {
        // For string content, wrap in a map
        _blocks[blockIndex] = block.copyWith(
          content: {'text': content},
          order: order
        );
      }
    });
    
    // Reset the flag after a short delay
    Future.delayed(const Duration(milliseconds: 250), () {
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
      _logger.debug('New block will have order: $newOrder');
      
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
    _scrollDebouncer?.cancel();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
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
    if (_editorProvider != null) {
      _editorProvider!.deactivate();
      _editorProvider!.dispose();
      _editorProvider = null;
    }
    
    // Dispose controllers
    _titleController.dispose();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBarCommon(
        onBackPressed: () {
          _saveAllContent();
          Navigator.pop(context);
        },
        title: _titleController.text.isEmpty ? 'Untitled Note' : _titleController.text,
        titleEditAction: IconButton(
          icon: Icon(
            Icons.edit,
            // Use appropriate color from theme
            color: theme.appBarTheme.actionsIconTheme?.color ?? 
                  theme.appBarTheme.foregroundColor ??
                  theme.colorScheme.onPrimary,
            size: 20, // Slightly smaller to look good next to title
          ),
          tooltip: 'Edit title',
          constraints: const BoxConstraints(), // Remove padding
          padding: const EdgeInsets.only(left: 8.0), // Add a little space between title and icon
          onPressed: () {
            // Show a dialog to edit the title
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Edit Title'),
                content: TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    hintText: 'Note Title',
                  ),
                  autofocus: true,
                ),
                actions: [
                  TextButton(
                    child: const Text('CANCEL'),
                    onPressed: () => Navigator.pop(context),
                  ),
                  TextButton(
                    child: const Text('SAVE'),
                    onPressed: () {
                      _saveTitle();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            );
          },
        ),
        // Add loading indicator to app bar when loading more blocks
        additionalActions: _loadingMoreBlocks ? [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(width: 16),
        ] : [],
      ),
      body: Theme(
        // Apply explicit text color overrides for dark mode to ensure visibility
        data: isDarkMode
            ? Theme.of(context).copyWith(
                textTheme: Theme.of(context).textTheme.apply(
                  bodyColor: Colors.white,
                  displayColor: Colors.white,
                ),
                // Also update the primary text theme for all text widgets
                primaryTextTheme: Theme.of(context).primaryTextTheme.apply(
                  bodyColor: Colors.white,
                  displayColor: Colors.white,
                ),
              )
            : Theme.of(context),
        child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : _blocks.isEmpty
                ? _buildEmptyState()
                : _buildEditor(),
      ),
    );
  }
  
  // Build the editor widget with scroll controller
  Widget _buildEditor() {
    // Create provider if it doesn't exist
    if (_editorProvider == null) {
      _createEditorProvider();
    }
    
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // Force text color in the editor based on theme
    return DefaultTextStyle(
      style: TextStyle(
        color: isDarkMode ? Colors.white : Colors.black,
        fontSize: 16,
      ),
      child: _editorProvider != null
          ? Column(
              children: [
                Expanded(
                  child: RichTextEditor(
                    provider: _editorProvider!,
                    scrollController: _scrollController,
                  ),
                ),
                // Loading indicator at the bottom when fetching more blocks
                if (_loadingMoreBlocks)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            )
          : const Center(child: Text('Error initializing editor')),
    );
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
