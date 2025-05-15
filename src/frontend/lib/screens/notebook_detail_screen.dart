import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:owlistic/viewmodel/notebooks_viewmodel.dart';
import 'package:owlistic/viewmodel/notes_viewmodel.dart';
import 'package:owlistic/models/note.dart';
import 'package:owlistic/models/notebook.dart';
import 'package:owlistic/utils/logger.dart';
import 'package:owlistic/widgets/card_container.dart';
import 'package:owlistic/widgets/empty_state.dart';
import 'note_editor_screen.dart';
import 'package:owlistic/widgets/app_drawer.dart';
import 'package:owlistic/widgets/app_bar_common.dart';

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
  
  // ViewModels
  late NotebooksViewModel _notebooksViewModel;
  late NotesViewModel _notesViewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    if (!_isInitialized) {
      _isInitialized = true;
      
      // Get ViewModels
      _notebooksViewModel = context.read<NotebooksViewModel>();
      _notesViewModel = context.read<NotesViewModel>();
      
      // Initialize data
      _initializeData();
    }
  }
  
  Future<void> _initializeData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Activate the ViewModels
      _notebooksViewModel.activate();
      _notesViewModel.activate();
      
      // Fetch notebook data with its notes
      await _notebooksViewModel.fetchNotebookById(widget.notebookId);
      
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

  void _showAddNoteDialog(BuildContext context, String notebookId) {
    final titleController = TextEditingController();

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
          controller: titleController,
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
              if (titleController.text.isNotEmpty) {
                try {
                  await _notebooksViewModel.addNoteToNotebook(
                    notebookId,
                    titleController.text,
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
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // Use Consumer for reactive UI updates based on ViewModel changes
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Consumer<NotebooksViewModel>(
          builder: (context, notebooksViewModel, _) {
            // Find the current notebook
            final notebook = notebooksViewModel.notebooks
                .where((nb) => nb.id == widget.notebookId)
                .firstOrNull;    
            return AppBarCommon(
              title: notebook?.name ?? 'Notebook',
              onBackPressed: () => context.go('/notebooks'),
              // Add this line to make hamburger menu clickable
              onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
            );
          }
        ),
      ),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Consumer<NotebooksViewModel>(
              builder: (context, notebooksViewModel, _) {
                // Find the current notebook
                final notebook = notebooksViewModel.getNotebook(widget.notebookId);
                
                if (notebook == null) {
                  return EmptyState(
                    title: 'Notebook not found',
                    message: 'This notebook may have been deleted or you don\'t have access to it.',
                    icon: Icons.folder_off,
                    onAction: () => context.go('/notebooks'),
                    actionLabel: 'Back to Notebooks',
                  );
                }
                
                return _buildNotebookContent(context, notebook);
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddNoteDialog(context, widget.notebookId),
        tooltip: 'Add Note',
        child: const Icon(Icons.add),
      ),
    );
  }
  
  Widget _buildNotebookContent(BuildContext context, Notebook notebook) {
    // Change dynamic type to proper Notebook type
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
                    } else if (value == 'move') {
                      _showMoveNoteDialog(context, note);
                    }
                  },
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem<String>(
                      value: 'move',
                      child: ListTile(
                        leading: Icon(Icons.drive_file_move),
                        title: Text('Move'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete, color: Colors.red),
                        title: Text('Delete', style: TextStyle(color: Colors.red)),
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
                // Use _notesViewModel instead of _notebooksViewModel
                await _notesViewModel.deleteNote(note.id);
                Navigator.of(ctx).pop();
                
                // Also refresh the notebook to update the UI
                await _notebooksViewModel.fetchNotebookById(widget.notebookId);
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
  
  // Add this new method to handle moving notes between notebooks
  void _showMoveNoteDialog(BuildContext context, Note note) {
    String? selectedNotebookId;
    
    // Get list of notebooks excluding current one
    final notebooks = _notebooksViewModel.notebooks
        .where((nb) => nb.id != widget.notebookId)
        .toList();
        
    if (notebooks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other notebooks available to move to'))
      );
      return;
    }
    
    // Default to first notebook
    selectedNotebookId = notebooks.first.id;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move Note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Select a notebook to move "${note.title}" to:'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Destination Notebook',
                prefixIcon: Icon(Icons.book),
              ),
              value: selectedNotebookId,
              items: notebooks.map((notebook) {
                return DropdownMenuItem<String>(
                  value: notebook.id,
                  child: Text(notebook.name),
                );
              }).toList(),
              onChanged: (value) {
                selectedNotebookId = value;
              },
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
              if (selectedNotebookId != null) {
                try {
                  Navigator.of(ctx).pop();
                  // Use _notesViewModel instead of _notebooksViewModel
                  await _notesViewModel.moveNote(note.id, selectedNotebookId!);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Note moved successfully')),
                  );
                } catch (e) {
                  _logger.error('Error moving note', e);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error moving note: ${e.toString()}')),
                  );
                }
              }
            },
            child: const Text('Move'),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    // Deactivate the ViewModels
    if (_isInitialized) {
      _notebooksViewModel.deactivate();
      _notesViewModel.deactivate();
    }
    
    super.dispose();
  }
}
