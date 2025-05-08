import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/notebook.dart';
import '../models/note.dart';
import '../utils/logger.dart';
import '../widgets/app_bar_common.dart';
import '../widgets/app_drawer.dart';
import '../widgets/empty_state.dart';
import '../viewmodel/notebooks_viewmodel.dart';
import '../widgets/theme_switcher.dart';
import 'note_editor_screen.dart';

class NotebooksScreen extends StatefulWidget {
  const NotebooksScreen({Key? key}) : super(key: key);

  @override
  State<NotebooksScreen> createState() => _NotebooksScreenState();
}

class _NotebooksScreenState extends State<NotebooksScreen> {
  final Logger _logger = Logger('NotebooksScreen');
  bool _isInitialized = false;
  late NotebooksViewModel _notebooksViewModel;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  // Track expanded notebooks
  final Set<String> _expandedNotebooks = {};
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    if (!_isInitialized) {
      _isInitialized = true;
      
      // Get ViewModel
      _notebooksViewModel = context.read<NotebooksViewModel>();
      
      // Activate ViewModel and fetch data
      _notebooksViewModel.activate();
      _notebooksViewModel.fetchNotebooks();
      
      _logger.info('NotebooksViewModel activated and initial data fetched');
    } else {
      // Ensure provider is active when screen is visible, even on subsequent dependencies change
      if (!_notebooksViewModel.isActive) {
        _notebooksViewModel.activate();
        _logger.info('NotebooksViewModel re-activated');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use Consumer for reactive UI updates
    return Scaffold(
      key: _scaffoldKey, 
      appBar: AppBarCommon(
        title: 'Notebooks',
        showBackButton: false,
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
        actions: const [ThemeSwitcher()],
      ),
      drawer: const AppDrawer(),
      body: Consumer<NotebooksViewModel>(
        builder: (context, viewModel, _) {
          return _buildContent(context, viewModel);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddNotebookDialog(context),
        tooltip: 'Add Notebook',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildContent(BuildContext context, NotebooksViewModel viewModel) {
    // Observe isLoading and notebooks property
    final isLoading = viewModel.isLoading;
    final notebooks = viewModel.notebooks;
    final errorMessage = viewModel.errorMessage;

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $errorMessage'),
            ElevatedButton(
              onPressed: () => viewModel.fetchNotebooks(),
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (notebooks.isEmpty) {
      return EmptyState(
        icon: Icons.book,
        title: 'No Notebooks',
        message: 'Create your first notebook to start organizing your notes.',
        actionLabel: 'Create Notebook',
        onAction: () => _showAddNotebookDialog(context),
      );
    }

    return RefreshIndicator(
      onRefresh: () => viewModel.fetchNotebooks(),
      child: ListView.builder(
        itemCount: notebooks.length,
        padding: const EdgeInsets.all(12.0),
        itemBuilder: (context, index) {
          final notebook = notebooks[index];
          return _buildNotebookCard(context, notebook);
        },
      ),
    );
  }

  Widget _buildNotebookCard(BuildContext context, Notebook notebook) {
    final isExpanded = _expandedNotebooks.contains(notebook.id);
    final hasNotes = notebook.notes.isNotEmpty;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Notebook item
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedNotebooks.remove(notebook.id);
                } else {
                  _expandedNotebooks.add(notebook.id);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
              child: Row(
                children: [
                  // Expand/collapse arrow
                  Icon(
                    isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                    color: hasNotes ? Theme.of(context).primaryColor : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  // Notebook icon
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.book,
                      size: 18,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Notebook name and count
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notebook.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        Text(
                          '${notebook.notes.length} note${notebook.notes.length != 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Actions for notebook
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    iconSize: 20,
                    splashRadius: 20,
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showEditNotebookDialog(context, notebook);
                      } else if (value == 'delete') {
                        _confirmDeleteNotebook(context, notebook);
                      }
                    },
                    itemBuilder: (BuildContext context) => [
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit),
                          title: Text('Edit Notebook'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline, color: Colors.red),
                          title: Text('Delete Notebook', style: TextStyle(color: Colors.red)),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ),
        // Notes list (when expanded)
        if (isExpanded)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: Column(
              children: [
                ...notebook.notes.map((note) => _buildNoteItem(context, note)),
                if (notebook.notes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 54.0, top: 8.0, bottom: 12.0),
                    child: Text(
                      'No notes in this notebook',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontSize: 13,
                      ),
                    ),
                  ),
                // Add note button
                InkWell(
                  onTap: () => _showAddNoteDialog(context, notebook.id),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 54.0, top: 4.0, bottom: 12.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add,
                          size: 16,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Add note',
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        Divider(height: 1, color: Theme.of(context).dividerColor.withOpacity(0.3)),
      ],
    );
  }

  Widget _buildNoteItem(BuildContext context, Note note) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _navigateToNoteEditor(context, note),
        child: Padding(
          padding: const EdgeInsets.only(left: 54.0, top: 8.0, bottom: 8.0, right: 16.0),
          child: Row(
            children: [
              // Note icon
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.description,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 12),
              // Note title and preview
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title.isEmpty ? 'Untitled Note' : note.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).textTheme.titleMedium?.color,
                      ),
                    ),
                    if (note.blocks.isNotEmpty)
                      Text(
                        note.blocks.first.getTextContent(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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

  void _showAddNotebookDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Notebook'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Enter notebook name',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Enter notebook description',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final description = descriptionController.text.trim();
              
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Name is required')),
                );
                return;
              }
              
              Navigator.pop(context);
              
              try {
                final viewModel = context.read<NotebooksViewModel>();
                await viewModel.createNotebook(name, description);
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Notebook created')),
                  );
                }
              } catch (e) {
                _logger.error('Error creating notebook', e);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString()}')),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showEditNotebookDialog(BuildContext context, Notebook notebook) {
    final nameController = TextEditingController(text: notebook.name);
    final descriptionController = TextEditingController(text: notebook.description);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Notebook'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Enter notebook name',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Enter notebook description',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final description = descriptionController.text.trim();
              
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Name is required')),
                );
                return;
              }
              
              Navigator.pop(context);
              
              try {
                final viewModel = context.read<NotebooksViewModel>();
                await viewModel.updateNotebook(notebook.id, name, description);
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Notebook updated')),
                  );
                }
              } catch (e) {
                _logger.error('Error updating notebook', e);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString()}')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteNotebook(BuildContext context, Notebook notebook) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Notebook?'),
        content: Text(
          'Are you sure you want to delete "${notebook.name}"? This action cannot be undone and will delete all notes in this notebook.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              
              try {
                final viewModel = context.read<NotebooksViewModel>();
                await viewModel.deleteNotebook(notebook.id);
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Notebook deleted')),
                  );
                }
              } catch (e) {
                _logger.error('Error deleting notebook', e);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString()}')),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    // Deactivate the ViewModel
    _notebooksViewModel.deactivate();
    super.dispose();
  }
}
