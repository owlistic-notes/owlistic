import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/note.dart';
import '../models/notebook.dart';
import '../providers/notebooks_provider.dart';
import '../providers/websocket_provider.dart';
import '../utils/provider_extensions.dart';
import '../utils/logger.dart';
import '../core/theme.dart';
import '../widgets/card_container.dart';
import '../widgets/empty_state.dart';
import 'note_editor_screen.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_bar_common.dart';

/// NotebookDetailScreen acts as the View in MVP pattern
class NotebookDetailScreen extends StatefulWidget {
  final String notebookId;

  const NotebookDetailScreen({Key? key, required this.notebookId}) : super(key: key);

  @override
  _NotebookDetailScreenState createState() => _NotebookDetailScreenState();
}

class _NotebookDetailScreenState extends State<NotebookDetailScreen> {
  final Logger _logger = Logger('NotebookDetailScreen');
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isInitialized = false;
  bool _isLoading = true;
  
  // NotebooksProvider acts as the Presenter
  late NotebooksProvider _presenter;
  late WebSocketProvider _webSocketProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    if (!_isInitialized) {
      _isInitialized = true;
      
      // Get presenters
      _presenter = context.notebooksPresenter();
      _webSocketProvider = context.webSocketProvider();
      
      // Initialize data
      _initializeData();
    }
  }
  
  Future<void> _initializeData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Ensure WebSocket connection first
      await _webSocketProvider.ensureConnected();
      
      // Activate the presenter
      _presenter.activate();
      
      // Subscribe to the notebook and notes events
      _webSocketProvider.subscribe('notebook', id: widget.notebookId);
      
      // Also subscribe to general note events to catch updates
      _webSocketProvider.subscribe('note.created');
      _webSocketProvider.subscribe('note.deleted');
      
      // Set up event handlers for automatic updates
      _setupEventHandlers();
      
      // Fetch notebook data
      await _presenter.fetchNotebookById(widget.notebookId);
      
      _logger.info('Initialized with notebook ID ${widget.notebookId}');
    } catch (e) {
      _logger.error('Error initializing notebook detail screen', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load notebook data'))
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  void _setupEventHandlers() {
    // Set up event handlers for real-time updates
    _webSocketProvider.addEventListener('event', 'note.created', (message) {
      _logger.info('Note created event received');
      _refreshNotebook();
    });
    
    _webSocketProvider.addEventListener('event', 'note.updated', (message) {
      _logger.info('Note updated event received');
      _refreshNotebook();
    });
    
    _webSocketProvider.addEventListener('event', 'note.deleted', (message) {
      _logger.info('Note deleted event received');
      _refreshNotebook();
    });
    
    _webSocketProvider.addEventListener('event', 'notebook.updated', (message) {
      _logger.info('Notebook updated event received');
      _refreshNotebook();
    });
  }
  
  Future<void> _refreshNotebook() async {
    if (!mounted) return;
    
    try {
      await _presenter.fetchNotebookById(widget.notebookId);
    } catch (e) {
      _logger.error('Error refreshing notebook', e);
    }
  }

  void _showAddNoteDialog(BuildContext context, String notebookId) {
    final _titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.note_add, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            const Text('Add Note'),
          ],
        ),
        content: TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Title',
            prefixIcon: Icon(Icons.title),
            hintText: 'Enter note title',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_titleController.text.isNotEmpty) {
                try {
                  await _presenter.addNoteToNotebook(
                    notebookId,
                    _titleController.text,
                  );
                  Navigator.of(ctx).pop();
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to create note')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showSortOptionsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              width: 40,
              margin: const EdgeInsets.only(top: 8, bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                'Sort By',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            const Divider(),
            _buildSortOption(context, 'Title (A to Z)', Icons.sort_by_alpha),
            _buildSortOption(context, 'Title (Z to A)', Icons.sort),
            _buildSortOption(context, 'Date (Newest First)', Icons.calendar_today),
            _buildSortOption(context, 'Date (Oldest First)', Icons.calendar_view_day),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(BuildContext context, String title, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).iconTheme.color),
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
      },
    );
  }

  void _navigateToNoteEditor(BuildContext context, Note note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NoteEditorScreen(note: note),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to notebooks provider for data updates
    final notebooksPresenter = context.notebooksPresenter(listen: true);
    
    // Find the current notebook
    final notebookIndex = notebooksPresenter.notebooks
        .indexWhere((nb) => nb.id == widget.notebookId);
    
    final hasNotebook = notebookIndex != -1;
    final notebook = hasNotebook 
        ? notebooksPresenter.notebooks[notebookIndex]
        : null;
    
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBarCommon(
        title: hasNotebook ? notebook!.name : 'Notebook',
        onBackPressed: () => context.go('/notebooks'), // Go back to notebooks list
      ),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !hasNotebook
              ? EmptyState(
                  title: 'Notebook not found',
                  message: 'This notebook may have been deleted or you don\'t have access to it.',
                  icon: Icons.folder_off,
                  onAction: () => context.go('/notebooks'),
                  actionLabel: 'Back to Notebooks',
                )
              : _buildNotebookContent(context, notebook!),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddNoteDialog(context, widget.notebookId),
        tooltip: 'Add Note',
        child: const Icon(Icons.add),
      ),
    );
  }
  
  Widget _buildNotebookContent(BuildContext context, dynamic notebook) {
    if (notebook.notes.isEmpty) {
      return EmptyState(
        title: 'No notes yet',
        message: 'Create your first note in this notebook.',
        icon: Icons.note_add,
        onAction: () => _showAddNoteDialog(context, notebook.id),
        actionLabel: 'Create Note',
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Notes (${notebook.notes.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              IconButton(
                icon: const Icon(Icons.sort),
                onPressed: () => _showSortOptionsBottomSheet(context),
                tooltip: 'Sort notes',
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: notebook.notes.length,
            itemBuilder: (context, index) {
              final note = notebook.notes[index];
              return CardContainer(
                onTap: () => _navigateToNoteEditor(context, note),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.description,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                title: note.title.isEmpty ? 'Untitled Note' : note.title,
                subtitle: 'Last edited',
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'delete') {
                      _showDeleteConfirmation(context, note);
                    }
                  },
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete),
                        title: Text('Delete'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                child: note.blocks.isNotEmpty
                  ? Text(
                      note.blocks.first.getTextContent(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Container(),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showDeleteConfirmation(BuildContext context, Note note) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Note'),
        content: Text('Are you sure you want to delete "${note.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            onPressed: () async {
              try {
                // Fix the method call to use the proper method
                await _presenter.deleteNote(widget.notebookId, note.id);
                Navigator.of(ctx).pop();
              } catch (error) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to delete note')),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    // Unsubscribe and deactivate when the view is disposed
    if (_isInitialized) {
      _webSocketProvider.removeEventListener('event', 'note.created');
      _webSocketProvider.removeEventListener('event', 'note.updated');
      _webSocketProvider.removeEventListener('event', 'note.deleted');
      _webSocketProvider.removeEventListener('event', 'notebook.updated');
      
      _webSocketProvider.unsubscribe('notebook', id: widget.notebookId);
      _webSocketProvider.unsubscribe('note.created');
      _webSocketProvider.unsubscribe('note.deleted');
      
      // Deactivate the presenter
      _presenter.deactivate();
    }
    
    super.dispose();
  }
}
