import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/notebook.dart';
import '../utils/logger.dart';
import '../widgets/app_bar_common.dart';
import '../widgets/app_drawer.dart';
import '../widgets/empty_state.dart';
import '../viewmodel/notebooks_viewmodel.dart';

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
        padding: const EdgeInsets.all(8.0),
        itemBuilder: (context, index) {
          final notebook = notebooks[index];
          return _buildNotebookCard(context, notebook);
        },
      ),
    );
  }

  Widget _buildNotebookCard(BuildContext context, Notebook notebook) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      elevation: 2.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        leading: const CircleAvatar(
          child: Icon(Icons.book),
        ),
        title: Text(notebook.name),
        subtitle: Text(
          'Notes: ${notebook.notes.length} · Created: ${_formatDate(notebook.createdAt!)}',
        ),
        onTap: () => context.go('/notebooks/${notebook.id}'),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
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
                title: Text('Edit'),
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
      ),
    );
  }

  void _showNotebookOptions(BuildContext context, Notebook notebook) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit Notebook'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditNotebookDialog(context, notebook);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Notebook', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteNotebook(context, notebook);
                },
              ),
            ],
          ),
        );
      },
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

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
  
  @override
  void dispose() {
    // Deactivate the ViewModel
    _notebooksViewModel.deactivate();
    super.dispose();
  }
}
