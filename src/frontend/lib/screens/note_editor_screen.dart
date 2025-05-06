import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note.dart';
import '../utils/logger.dart';
import '../widgets/app_bar_common.dart';
import '../viewmodel/note_editor_viewmodel.dart';
import '../widgets/theme_switcher.dart';

class NoteEditorScreen extends StatefulWidget {
  final String? noteId;
  final Note? note;
  
  const NoteEditorScreen({Key? key, this.noteId, this.note}) : super(key: key);
  
  @override
  _NoteEditorScreenState createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final Logger _logger = Logger('NoteEditorScreen');
  bool _isLoading = true;
  String? _errorMessage;
  Note? _note;
  Timer? _autoSaveTimer;
  bool _titleEdited = false;
  final TextEditingController _titleController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  late String? _noteId;
  
  // ScrollController for the editor
  final ScrollController _scrollController = ScrollController();
  
  // Provider
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
    
    // Only initialize dependencies once
    if (!_isInitialized) {
      // Get ViewModel
      _noteEditorViewModel = context.read<NoteEditorViewModel>();
      _isInitialized = true;
    }
  }

  Future<void> _initialize() async {
    // Activate ViewModel
    _noteEditorViewModel.activate();
    
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
      
      // Set the note ID in the editor
      _noteEditorViewModel.noteId = _noteId;
      
      // Load initial blocks for the note using ViewModel
      await _noteEditorViewModel.fetchBlocksForNote(_noteId!, page: 1, pageSize: 20);
      
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

  // Simplified method for loading more blocks in the background
  Future<void> _loadMoreBlocksInBackground() async {
    if (_noteId == null || !mounted) return;
    
    try {
      // Get current pagination state
      final paginationInfo = _noteEditorViewModel.getPaginationInfo(_noteId!);
      final currentPage = paginationInfo['page'] as int? ?? 1;
      final nextPage = currentPage + 1;
      
      // Check if there are more blocks to load
      if (!_noteEditorViewModel.hasMoreBlocks(_noteId!)) {
        return;
      }
      
      _logger.info('Loading more blocks in background (page: $nextPage)');
      
      // Fetch the next page with append=true to keep existing blocks
      final moreBlocks = await _noteEditorViewModel.fetchBlocksForNote(
        _noteId!,
        page: nextPage,
        pageSize: 20,
        append: true
      );
      
      // Log the result for debugging
      _logger.debug('Received ${moreBlocks.length} blocks for page $nextPage');
      
      // Simple check - if ViewModel says there are more blocks, load them after a short delay
      if (moreBlocks.isNotEmpty && _noteEditorViewModel.hasMoreBlocks(_noteId!)) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          _loadMoreBlocksInBackground();
        }
      }
    } catch (e) {
      _logger.error('Error loading more blocks', e);
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
    
    // Save any pending changes
    _autoSaveTitleIfNeeded();
    _noteEditorViewModel.commitAllContent();
    
    // Deactivate ViewModel
    if (_isInitialized) {
      _noteEditorViewModel.deactivate();
    }
    
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
      // Get document position directly from the ViewModel
      final verticalOffset = _noteEditorViewModel.documentBuilder.getNodePosition(blockId);
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

  // Build the rich text editor directly, without using a separate widget
  Widget _buildRichTextEditor(NoteEditorViewModel viewModel) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        // Check if we're near the bottom of the scroll view to trigger loading more blocks
        if (_noteId != null &&
            viewModel.hasMoreBlocks(_noteId!) &&
            scrollInfo.metrics.pixels > scrollInfo.metrics.maxScrollExtent * 0.8) {
          // Simplified trigger for loading more blocks
          _loadMoreBlocksInBackground();
        }
        return false;
      },
      // Use DocumentBuilder's createSuperEditor method
      child: viewModel.documentBuilder.createSuperEditor(
        readOnly: false,
        scrollController: _scrollController,
        themeData: Theme.of(context), // Pass the current theme to ensure proper text colors
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Add AppBarCommon with ONLY theme switching functionality
      appBar: const AppBarCommon(
        title: '',  // Empty title as we have our own title field
        showBackButton: false,  // No back button in app bar
        actions: [ThemeSwitcher()],
      ),
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
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), // Add extra top padding to account for status bar
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
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
