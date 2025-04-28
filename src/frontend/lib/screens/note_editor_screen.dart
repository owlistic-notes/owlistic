import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../models/note.dart';
import '../models/block.dart';
import '../utils/logger.dart';
import '../widgets/app_bar_common.dart';
import '../viewmodel/note_editor_viewmodel.dart';  // Only reference NoteEditorViewModel
import '../utils/websocket_subscription_manager.dart';
import 'package:super_editor/super_editor.dart' hide Logger;

class NoteEditorScreen extends StatefulWidget {
  final String? noteId;
  final Note? note;
  
  const NoteEditorScreen({Key? key, this.noteId, this.note}) : super(key: key);
  
  @override
  _NoteEditorScreenState createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> with WebSocketSubscriptionMixin {
  final Logger _logger = Logger('NoteEditorScreen');
  bool _isLoading = true;
  bool _isLoadingMoreBlocks = false;
  String? _errorMessage;
  Note? _note;
  Timer? _autoSaveTimer;
  bool _titleEdited = false;
  final TextEditingController _titleController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  late String? _noteId;
  
  // ScrollController for the editor
  final ScrollController _scrollController = ScrollController();
  
  // Only use NoteEditorViewModel
  late NoteEditorViewModel _noteEditorViewModel;
  
  // Flag to track initialization
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    
    // Get note ID from either the direct note prop or the ID prop
    _noteId = widget.note?.id ?? widget.noteId;
    
    // Initialize with note data if provided directly
    if (widget.note != null) {
      _note = widget.note;
      _titleController.text = _note!.title;
    }
    
    // Set up autoSave timer
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _autoSaveTitleIfNeeded();
    });
    
    // Setup title focus listener
    _titleFocusNode.addListener(_handleTitleFocusChange);
    
    // Initialize ViewModels and data with a post-frame callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Only initialize WebSocket subscriptions after dependencies are available
    // and if not already initialized
    if (!_isInitialized) {
      // Safe to initialize WebSocket subscriptions now
      initWebSocketSubscriptions();
    }
  }

  Future<void> _initialize() async {
    // Get ViewModels
    _noteEditorViewModel = context.read<NoteEditorViewModel>();
    
    // Activate ViewModels
    _noteEditorViewModel.activate();
    
    // Setup WebSocket subscriptions after providers are available
    if (_noteId != null) {
      subscribe('note', id: _noteId);
      subscribeToEvent('block.created');
      subscribeToEvent('block.updated');
      subscribeToEvent('block.deleted');
    }
    
    try {
      if (_noteId == null || _noteId!.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Note ID is required';
        });
        return;
      }
      
      // If we don't have the note data yet, fetch it
      if (_note == null) {
        _note = await _noteEditorViewModel.fetchNoteById(_noteId!);
        
        if (_note == null) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Note not found';
          });
          return;
        }
        
        // Set the title
        _titleController.text = _note!.title;
      }
      
      // Activate the note in the ViewModel
      _noteEditorViewModel.activateNote(_noteId!);
      
      // Set the note ID in the editor
      _noteEditorViewModel.noteId = _noteId;
      
      // Load initial blocks for the note using ViewModel - use smaller page size for faster initial rendering
      final blocks = await _noteEditorViewModel.fetchBlocksForNote(_noteId!, page: 1, pageSize: 20);
      
      _isInitialized = true;
      
      setState(() {
        _isLoading = false;
      });
      
      // Load more blocks in the background if available
      _loadMoreBlocksInBackground();
    } catch (e) {
      _logger.error('Error initializing note editor', e);
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading note: ${e.toString()}';
      });
    }
  }

  // Fixed method for loading more blocks in the background
  Future<void> _loadMoreBlocksInBackground() async {
    // Guard against concurrent loading operations
    if (_isLoadingMoreBlocks) return;
    
    try {
      if (_noteId == null || !mounted) return;
      
      setState(() {
        _isLoadingMoreBlocks = true;
      });

      // If we have more blocks to load
      if (_noteEditorViewModel.hasMoreBlocks(_noteId!)) {
        _logger.info('Loading more blocks in background');
        
        // Get current pagination state
        final paginationInfo = _noteEditorViewModel.getPaginationInfo(_noteId!);
        
        // Safely access the page number with null check and fallback
        final currentPage = paginationInfo['page'] ?? 1;
        if (currentPage is! int) {
          _logger.error('Invalid page number in pagination info: $currentPage');
          setState(() {
            _isLoadingMoreBlocks = false;
          });
          return;
        }
        
        final nextPage = currentPage + 1;
        
        // Fetch the next page with append=true to keep existing blocks
        final moreBlocks = await _noteEditorViewModel.fetchBlocksForNote(
          _noteId!,
          page: nextPage,
          pageSize: 20,
          append: true
        );
        
        // Complete the loading operation
        setState(() {
          _isLoadingMoreBlocks = false;
        });
        
        // IMPORTANT FIX: If we received empty response, mark as end of data
        if (moreBlocks.isEmpty) {
          _logger.info('No more blocks returned from API, ending pagination');
          return;
        }

        // Check if we got fewer blocks than requested, which means we've reached the end
        if (_noteEditorViewModel.hasMoreBlocks(_noteId!)) {
          // Add a short delay before loading more to prevent UI freezing
          await Future.delayed(const Duration(milliseconds: 500));
          // Start another load cycle, but only if we're still mounted
          if (mounted) {
            _loadMoreBlocksInBackground();
          }
        } else {
          _logger.info('Finished loading blocks. Total blocks loaded ${moreBlocks.length}');
        }
      } else {
        setState(() {
          _isLoadingMoreBlocks = false;
        });
        _logger.info('No more blocks to load according to pagination info');
      }
    } catch (e) {
      _logger.error('Error loading more blocks', e);
      setState(() {
        _isLoadingMoreBlocks = false;
      });
    }
  }

  @override
  void dispose() {
    // Clean up
    _autoSaveTimer?.cancel();
    _titleFocusNode.removeListener(_handleTitleFocusChange);
    _titleFocusNode.dispose();
    _titleController.dispose();
    _scrollController.dispose();
    
    _noteEditorViewModel.deactivate();
    _autoSaveTitleIfNeeded();
    
    // WebSocketSubscriptionMixin handles subscription cleanup in its dispose method
    super.dispose();
  }

  // Handle title focus change
  void _handleTitleFocusChange() {
    if (!_titleFocusNode.hasFocus) {
      _autoSaveTitleIfNeeded();
    }
  }

  // Auto-save title if it's been edited
  void _autoSaveTitleIfNeeded() {
    if (_titleEdited && _note != null && mounted) {
      _saveTitle();
    }
  }

  // Save title
  void _saveTitle() async {
    if (_note == null || !_titleEdited) return;
    final newTitle = _titleController.text.trim();
    if (newTitle.isEmpty || newTitle == _note!.title) {
      _titleEdited = false;
      return;
    }
    try {
      // Use NoteEditorViewModel to update note title
      await _noteEditorViewModel.updateNoteTitle(_note!.id, newTitle);
      _titleEdited = false;
      _note = _noteEditorViewModel.currentNote;
      _logger.info('Title saved successfully');
    } catch (e) {
      _logger.error('Error saving title', e);
    }
  }

  // Helper method to scroll to a specific block when needed
  void _scrollToBlock(String blockId) {
    if (_scrollController.hasClients) {
      // Get the node ID associated with this block ID
      final nodeToBlockMap = _noteEditorViewModel.documentBuilder.nodeToBlockMap;
      String? targetNodeId;
      
      // Find the node ID for this block
      nodeToBlockMap.forEach((nodeId, mappedBlockId) {
        if (mappedBlockId == blockId) {
          targetNodeId = nodeId;
        }
      });
      
      // If we found the node, scroll to it
      if (targetNodeId != null) {
        final verticalOffset = _noteEditorViewModel.documentBuilder.getNodePosition(targetNodeId!);
        if (verticalOffset != null) {
          // Scroll to the node position with some padding
          _scrollController.animateTo(
            verticalOffset - 16.0, // Add some padding at the top
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }
    }
  }

  // Build the rich text editor directly, without using a separate widget
  Widget _buildRichTextEditor(NoteEditorViewModel viewModel) {
    // Access the document builder from the provider
    final documentBuilder = viewModel.documentBuilder;
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        // Check if we're near the bottom of the scroll view to trigger loading more blocks
        if (!_isLoadingMoreBlocks && // Only if we're not already loading
            scrollInfo.metrics.pixels > scrollInfo.metrics.maxScrollExtent * 0.8) {
          // Make sure we don't trigger multiple loading operations
          if (_noteId != null && _noteEditorViewModel.hasMoreBlocks(_noteId!)) {
            _loadMoreBlocksInBackground();
          }
        }
        return false;
      },
      child: SuperEditor(
        editor: documentBuilder.editor,
        documentLayoutKey: documentBuilder.documentLayoutKey,
        focusNode: documentBuilder.focusNode,
        scrollController: _scrollController,
        gestureMode: DocumentGestureMode.mouse,
        stylesheet: defaultStylesheet.copyWith(
          documentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Remove AppBarCommon and replace with no AppBar
      appBar: null, // Set to null to hide the app bar completely
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : (_errorMessage != null
          ? Center(child: Text('Error: $_errorMessage', style: TextStyle(color: Colors.red)))
          : Consumer<NoteEditorViewModel>(
              builder: (context, noteEditorViewModel, _) {
                // React to loading state
                final isContentLoading = noteEditorViewModel.isLoading;
                
                // Error handling
                final errorMessage = noteEditorViewModel.errorMessage;
                
                if (errorMessage != null) {
                  return Center(child: Text('Error: $errorMessage', style: TextStyle(color: Colors.red)));
                }

                // Check for specific block focus requests
                final focusBlockId = noteEditorViewModel.consumeFocusRequest();
                if (focusBlockId != null) {
                  _scrollToBlock(focusBlockId);
                }

                // Check if current note was updated from ViewModel
                if (noteEditorViewModel.currentNote != null && 
                    noteEditorViewModel.currentNote!.id == _noteId) {
                  _note = noteEditorViewModel.currentNote;
                }

                return Column(
                  children: [
                    // Title field - now functions as the "app bar" content
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 36, 16, 0), // Add extra top padding to account for status bar
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Back button
                          IconButton(
                            icon: Icon(Icons.arrow_back),
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                          ),
                          // Title field - expanded to take available space
                          Expanded(
                            child: TextField(
                              controller: _titleController,
                              focusNode: _titleFocusNode,
                              style: Theme.of(context).textTheme.headlineSmall,
                              decoration: const InputDecoration(
                                hintText: 'Note title',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 8),
                              ),
                              onChanged: (value) {
                                _titleEdited = true;
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    // Rich text editor
                    Expanded(
                      child: Stack(
                        children: [
                          // Editor content - using direct integration
                          _buildRichTextEditor(noteEditorViewModel),
                          // Loading overlay
                          if (isContentLoading)
                            const Center(child: CircularProgressIndicator()),
                        ],
                      ),
                    ),
                  ],
                );
              },
            )
        ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddBlockMenu(context),
        child: const Icon(Icons.add),
        tooltip: 'Add block',
      ),
    );
  }

  void _showAddBlockMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Text'),
              onTap: () {
                Navigator.pop(context);
                _createBlock('text');
              },
            ),
            ListTile(
              leading: const Icon(Icons.title),
              title: const Text('Heading'),
              onTap: () {
                Navigator.pop(context);
                _createBlock('heading');
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_box),
              title: const Text('Checklist'),
              onTap: () {
                Navigator.pop(context);
                _createBlock('checklist');
              },
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Code'),
              onTap: () {
                Navigator.pop(context);
                _createBlock('code');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createBlock(String blockType) async {
    try {
      // Make sure we wait for the block to actually be created on the server
      final block = await _noteEditorViewModel.createBlock(blockType);
      
      // Request focus after the block is fully created
      _noteEditorViewModel.setFocusToBlock(block.id);
      _logger.info('Block created: ${block.id} of type $blockType');
    } catch (e) {
      _logger.error('Error creating block', e);
    }
  }
}
