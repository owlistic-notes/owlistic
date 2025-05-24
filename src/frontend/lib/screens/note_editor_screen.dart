import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:owlistic/models/note.dart';
import 'package:owlistic/utils/logger.dart';
import 'package:owlistic/widgets/app_bar_common.dart';
import 'package:owlistic/viewmodel/note_editor_viewmodel.dart';
import 'package:owlistic/widgets/theme_switcher.dart';

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
    _noteEditorViewModel = context.read<NoteEditorViewModel>();
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

      // Activate the note in the ViewModel
      _noteEditorViewModel.activateNote(_noteId!);

      // Set the note ID in the editor
      _noteEditorViewModel.noteId = _noteId;

      // Load initial blocks for the note using ViewModel
      await _noteEditorViewModel.fetchBlocksForNote(_noteId!,
          page: 1, pageSize: 30);

      // Initialize the scroll listener for pagination - JUST ONCE
      _noteEditorViewModel.initScrollListener(_scrollController);

      _isInitialized = true;

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      _logger.error('Error initializing note editor', e);
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading note: ${e.toString()}';
      });
    }
  }

  @override
  void dispose() {
    // Clean up
    _titleFocusNode.removeListener(_handleTitleFocusChange);
    _titleFocusNode.dispose();
    _titleController.dispose();

    // Save any pending changes before disposing scroll controller
    _autoSaveTitleIfNeeded();
    _noteEditorViewModel.commitAllNodes();

    // Important: Dispose scroll controller AFTER using it to save content
    _scrollController.dispose();

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
      final verticalOffset =
          _noteEditorViewModel.documentBuilder.getNodePosition(blockId);
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
    // Remove redundant notification listener and use the scroll controller directly
    return viewModel.documentBuilder.createSuperEditor(
      readOnly: false,
      scrollController: _scrollController,
      themeData: Theme.of(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Add AppBarCommon with ONLY theme switching functionality
      appBar: AppBarCommon(
        title: '', // Empty title as we have our own title field
        showBackButton: false, // No back button in app bar
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh note content',
            onPressed: () => _noteEditorViewModel.fetchBlocksForNote(
                _noteEditorViewModel.noteId ?? '',
                refresh: true),
          ),
          const ThemeSwitcher(),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget? _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
          child: Text('Error: $_errorMessage',
              style: const TextStyle(color: Colors.red)));
    }
    return Consumer<NoteEditorViewModel>(
      builder: (context, noteEditorViewModel, _) {
        // Always update _note from viewModel to ensure we have latest data
        if (noteEditorViewModel.currentNote != null &&
            noteEditorViewModel.currentNote!.id == _noteId) {
          _note = noteEditorViewModel.currentNote;

          // Update title if changed from server
          if (_note != null &&
              _titleController.text != _note!.title &&
              !_titleFocusNode.hasFocus) {
            _titleController.text = _note!.title;
          }
        }

        // React to loading state
        final isContentLoading = noteEditorViewModel.isLoading;

        // Error handling
        final errorMessage = noteEditorViewModel.errorMessage;

        if (errorMessage != null) {
          return Center(
              child: Text('Error: $errorMessage',
                  style: const TextStyle(color: Colors.red)));
        }

        // Check for specific block focus requests
        final focusBlockId = noteEditorViewModel.consumeFocusRequest();
        if (focusBlockId != null) {
          _scrollToBlock(focusBlockId);
        }

        // Listen for update count changes to refresh UI
        final updateCount = noteEditorViewModel.updateCount;
        if (updateCount > 0) {
          // This will trigger a UI refresh when updateCount changes
          _logger.debug('Note editor update count: $updateCount');
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
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
            Expanded(
              child: Stack(
                children: [
                  _buildRichTextEditor(noteEditorViewModel),
                  if (isContentLoading)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}