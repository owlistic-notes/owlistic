import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/note.dart';
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
    // Ensure WebSocket connection first
    await _webSocketProvider.ensureConnected();
    
    // Activate the presenter
    _presenter.activate();
    
    // Subscribe to the notebook and notes events
    _webSocketProvider.subscribe('notebook', id: widget.notebookId);
    _webSocketProvider.subscribe('notebook:notes', id: widget.notebookId);
    
    // Also subscribe to general note events to catch updates
    _webSocketProvider.subscribe('note');
    _webSocketProvider.subscribe('note.created'); // Add specific event subscription
    _webSocketProvider.subscribe('note.deleted'); // Add specific event subscription
    
    // Fetch notebook data
    await _presenter.fetchNotebookById(widget.notebookId);
    
    _logger.info('Initialized with notebook ID ${widget.notebookId}');
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
            Icon(Icons.note_add_outlined, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            const Text('Add Note'),
          ],
        ),
        content: TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Title',
            prefixIcon: Icon(Icons.title),
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
                  await _presenter.addNoteToNotebook(notebookId, _titleController.text);
                  Navigator.of(ctx).pop();
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to create note')),
                  );
                }
              }
            },
            child: const Text('Create'),
            style: AppTheme.getSuccessButtonStyle(),
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sort Notes',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _buildSortOption(context, 'Date Created (Newest)', Icons.calendar_today),
            _buildSortOption(context, 'Date Created (Oldest)', Icons.calendar_today),
            _buildSortOption(context, 'Title (A-Z)', Icons.sort_by_alpha),
            _buildSortOption(context, 'Title (Z-A)', Icons.sort_by_alpha),
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
        // Implement sorting logic
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
        title: hasNotebook ? notebook!.name : 'Notebook Details',
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
        onBackPressed: () => context.go('/notebooks'), // Go back to notebooks list
      ),
      drawer: const AppDrawer(),
      body: !hasNotebook
          ? const Center(child: CircularProgressIndicator())
          : _buildNotebookContent(context, notebook!),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddNoteDialog(context, widget.notebookId),
        child: const Icon(Icons.add),
        tooltip: 'Add Note',
      ),
    );
  }
  
  Widget _buildNotebookContent(BuildContext context, dynamic notebook) {
    if (notebook.notes.isEmpty) {
      return EmptyState(
        title: 'No notes in this notebook',
        message: 'Create your first note to get started taking notes',
        icon: Icons.note_add_outlined,
        onAction: () => _showAddNoteDialog(context, widget.notebookId),
        actionLabel: 'Create Note',
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.folder,
                      color: Theme.of(context).primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notebook.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (notebook.description.isNotEmpty)
                          Text(
                            notebook.description,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    '${notebook.notes.length} Notes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _showSortOptionsBottomSheet(context),
                    icon: const Icon(Icons.sort),
                    label: const Text('Sort'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).textTheme.bodySmall?.color,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: notebook.notes.length,
            itemBuilder: (context, index) {
              final note = notebook.notes[index];
              return CardContainer(
                key: ValueKey('note_${note.id}'),
                onTap: () => _navigateToNoteEditor(context, note),
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
                trailing: IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: AppTheme.dangerColor,
                  ),
                  onPressed: () => _showDeleteConfirmation(context, note),
                ),
                child: note.blocks.isEmpty
                  ? const Text('Empty note', style: TextStyle(fontStyle: FontStyle.italic))
                  : Text(
                      note.blocks.first.getTextContent(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
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
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await _presenter.deleteNoteFromNotebook(widget.notebookId, note.id);
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
  void dispose() {
    // Unsubscribe and deactivate when the view is disposed
    if (_isInitialized) {
      _webSocketProvider.unsubscribe('notebook', id: widget.notebookId);
      _webSocketProvider.unsubscribe('notebook:notes', id: widget.notebookId);
      _webSocketProvider.unsubscribe('note.created');
      _webSocketProvider.unsubscribe('note.deleted');
      
      // Deactivate the presenter
      _presenter.deactivate();
    }
    
    super.dispose();
  }
}
