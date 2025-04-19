import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../widgets/app_drawer.dart';
import '../widgets/card_container.dart';
import '../widgets/empty_state.dart';
import '../models/note.dart';
import '../providers/websocket_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/notebooks_provider.dart';
import '../utils/provider_extensions.dart';
import '../utils/logger.dart';
import '../core/theme.dart';
import 'note_editor_screen.dart';
import '../widgets/app_bar_common.dart';

/// NotesScreen acts as the View in MVP pattern
class NotesScreen extends StatefulWidget {
  @override
  _NotesScreenState createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final Logger _logger = Logger('NotesScreen');
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isInitialized = false;
  int _currentPage = 1;
  bool _hasMoreData = true;
  bool _isLoadingMore = false;
  Set<String> _loadedNoteIds = {}; // Track loaded note IDs to prevent duplicates
  bool _isRefreshing = false; // Track refresh state to avoid multiple refreshes
  
  // NotesProvider acts as the Presenter
  late NotesProvider _presenter;
  late WebSocketProvider _wsProvider;
  
  @override
  void initState() {
    super.initState();
    
    // Add scroll listener for pagination
    _scrollController.addListener(_scrollListener);
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    if (!_isInitialized) {
      _isInitialized = true;
      
      // Get presenters
      _presenter = context.notesPresenter();
      _wsProvider = context.webSocketProvider();
      
      // Initialize WebSocket and fetch data
      _initializeData();
    }
  }
  
  Future<void> _initializeData() async {
    // Ensure WebSocket is connected 
    await _wsProvider.ensureConnected();
    
    // Register handlers for automatic refresh on events
    _registerEventHandlers();
    
    // Subscribe to events
    _wsProvider.subscribe('note');
    _wsProvider.subscribe('note.created');
    _wsProvider.subscribe('note.updated');
    _wsProvider.subscribe('note.deleted');
    
    // Activate the presenter
    _presenter.activate();
    
    // Fetch initial data
    await _refresh();
  }
  
  void _registerEventHandlers() {
    // Global handler for note creation and updates that will automatically refresh the notes list
    _wsProvider.addEventListener('event', 'note.created', (_) => _handleNoteEvent());
    _wsProvider.addEventListener('event', 'note.updated', (_) => _handleNoteEvent());
    _wsProvider.addEventListener('event', 'note.deleted', (_) => _handleNoteEvent());
    
    _logger.info('Registered event handlers for automatic refresh');
  }
  
  void _handleNoteEvent() {
    // Debounce refreshes to avoid multiple API calls for batch updates
    if (!_isRefreshing) {
      _isRefreshing = true;
      
      // Small delay to batch potential multiple events
      Future.delayed(const Duration(milliseconds: 300), () {
        _refresh().then((_) {
          _isRefreshing = false;
        }).catchError((e) {
          _isRefreshing = false;
        });
      });
    }
  }
  
  // Refresh notes data
  Future<void> _refresh() async {
    _logger.info('Refreshing notes data');
    _currentPage = 1;
    await _presenter.fetchNotes();
    _updateLoadedNoteIds();
  }
  
  // Update loaded note IDs to track what we've already loaded
  void _updateLoadedNoteIds() {
    setState(() {
      _loadedNoteIds = _presenter.notes.map((note) => note.id).toSet();
    });
  }
  
  // Process a single new note from WebSocket without full refresh
  void _handleNewNote(String noteId) {
    // Check if this note is already loaded
    if (_loadedNoteIds.contains(noteId)) {
      _logger.debug('Note $noteId already loaded, skipping');
      return;
    }
    
    _logger.info('Adding new note $noteId from WebSocket event');
    
    // Fetch just this one note and add it to the list
    _presenter.fetchNoteFromEvent(noteId).then((_) {
      // Update our tracking set
      _updateLoadedNoteIds();
    });
  }
  
  // Scroll listener for infinite scrolling
  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoadingMore && _hasMoreData) {
      _loadMoreNotes();
    }
  }
  
  // Load more notes for pagination
  Future<void> _loadMoreNotes() async {
    if (_isLoadingMore) return;
    
    setState(() {
      _isLoadingMore = true;
    });
    
    _currentPage++;
    final currentCount = _presenter.notes.length;
    final currentIds = _presenter.notes.map((note) => note.id).toSet();
    
    // Pass the currently loaded IDs to avoid fetching duplicates
    await _presenter.fetchNotes(
      page: _currentPage, 
      excludeIds: currentIds.toList(),
    );
    
    // Check if we got new data
    final hasNewData = _presenter.notes.length > currentCount;
    
    setState(() {
      _hasMoreData = hasNewData;
      _isLoadingMore = false;
    });
  }

  void _showAddNoteDialog() {
    final _titleController = TextEditingController();
    String? selectedNotebookId;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.note_add_outlined, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            const Text('Add Note'),
          ],
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Add notebook dropdown
            Consumer<NotebooksProvider>(
              builder: (context, notebooksProvider, _) {
                final notebooks = notebooksProvider.notebooks;
                
                // Show loading if notebooks aren't loaded yet
                if (notebooksProvider.isLoading) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                
                // If no notebooks, show message
                if (notebooks.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'You need to create a notebook first',
                      style: TextStyle(color: AppTheme.dangerColor),
                    ),
                  );
                }
                
                // Set the initial value if not set
                if (selectedNotebookId == null && notebooks.isNotEmpty) {
                  selectedNotebookId = notebooks.first.id;
                }
                
                return DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Notebook',
                    prefixIcon: Icon(Icons.folder_outlined),
                  ),
                  value: selectedNotebookId,
                  isExpanded: true,
                  items: notebooks.map((notebook) {
                    return DropdownMenuItem<String>(
                      value: notebook.id,
                      child: Text(
                        notebook.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    selectedNotebookId = value;
                  },
                );
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                prefixIcon: Icon(Icons.title),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_titleController.text.isNotEmpty && selectedNotebookId != null) {
                try {
                  await _presenter.createNote(selectedNotebookId!, _titleController.text);
                  Navigator.of(ctx).pop();
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to create note')),
                  );
                }
              } else {
                // Show error if no notebook is selected
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please select a notebook and enter a title')),
                );
              }
            },
            style: AppTheme.getSuccessButtonStyle(),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _navigateToNoteEditor(Note note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NoteEditorScreen(note: note),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, String noteId, String noteTitle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Note'),
        content: Text('Are you sure you want to delete "$noteTitle"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await _presenter.deleteNote(noteId);
              } catch (error) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to delete note')),
                );
              }
            },
            style: AppTheme.getDangerButtonStyle(),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to presenters for updates
    final notesPresenter = context.notesPresenter(listen: true);
    
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBarCommon(
        title: 'Notes',
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
        onBackPressed: () => Navigator.of(context).pop(),
      ),
      drawer: const AppDrawer(),
      body: _buildBody(notesPresenter),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddNoteDialog,
        child: const Icon(Icons.add),
        tooltip: 'Add Note',
      ),
    );
  }
  
  Widget _buildBody(NotesProvider presenter) {
    if (presenter.isLoading && presenter.notes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (presenter.notes.isEmpty) {
      return EmptyState(
        title: 'No notes found',
        message: 'Create your first note to get started',
        icon: Icons.note_add_outlined,
        onAction: _showAddNoteDialog,
        actionLabel: 'Create Note',
      );
    }
    
    return RefreshIndicator(
      onRefresh: _refresh, // Use our new refresh method
      color: Theme.of(context).primaryColor,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: presenter.notes.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          // Show loading indicator at the end
          if (index == presenter.notes.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          
          final note = presenter.notes[index];
          return CardContainer(
            key: ValueKey('note_${note.id}'),
            onTap: () => _navigateToNoteEditor(note),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.description_outlined,
                color: Theme.of(context).primaryColor,
              ),
            ),
            title: note.title,
            subtitle: note.notebookId,
            trailing: IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: AppTheme.dangerColor,
              ),
              onPressed: () => _showDeleteConfirmation(
                context, 
                note.id, 
                note.title,
              ),
            ),
            child: note.blocks.isEmpty
              ? const Text('Empty note', style: TextStyle(fontStyle: FontStyle.italic))
              : Text(
                  note.blocks.isNotEmpty ? note.blocks.first.getTextContent() : '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
          );
        },
      ),
    );
  }
  
  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    
    // Clean up WebSocket listeners
    if (_isInitialized) {
      _wsProvider.removeEventListener('event', 'note.created');
      _wsProvider.removeEventListener('event', 'note.updated');
      _wsProvider.removeEventListener('event', 'note.deleted');
      
      _wsProvider.unsubscribe('note');
      _wsProvider.unsubscribe('note.created');
      _wsProvider.unsubscribe('note.updated');
      _wsProvider.unsubscribe('note.deleted');
    }
    
    // Deactivate the presenter when the view is disposed
    _presenter.deactivate();
    
    super.dispose();
  }
}
