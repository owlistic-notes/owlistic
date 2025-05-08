import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/app_drawer.dart';
import '../widgets/card_container.dart';
import '../widgets/empty_state.dart';
import '../viewmodel/trash_viewmodel.dart';
import '../models/note.dart';
import '../models/notebook.dart';
import '../utils/logger.dart';
import '../widgets/app_bar_common.dart';
import 'package:intl/intl.dart';
import '../widgets/theme_switcher.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  _TrashScreenState createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final Logger _logger = Logger('TrashScreen');
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isInitialized = false;

  // ViewModel
  late TrashViewModel _trashViewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_isInitialized) {
      _isInitialized = true;

      // Get ViewModel
      _trashViewModel = context.read<TrashViewModel>();

      // Initialize data
      _initializeData();
    }
  }

  Future<void> _initializeData() async {
    try {
      _trashViewModel.activate();
      await _trashViewModel.fetchTrashedItems();
    } catch (e) {
      _logger.error('Error initializing TrashScreen', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBarCommon(
        title: 'Trash',
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
        showBackButton: false,
        actions: const [ThemeSwitcher()],
      ),
      drawer: const AppDrawer(),
      body: Consumer<TrashViewModel>(
        builder: (ctx, trashViewModel, _) {
          if (trashViewModel.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final hasNotes = trashViewModel.trashedNotes.isNotEmpty;
          final hasNotebooks = trashViewModel.trashedNotebooks.isNotEmpty;
          
          if (!hasNotes && !hasNotebooks) {
            return const EmptyState(
              title: 'Trash is Empty',
              message: 'Items that are moved to trash will appear here',
              icon: Icons.delete_outline,
              actionLabel: null,
            );
          }

          return RefreshIndicator(
            onRefresh: () => trashViewModel.fetchTrashedItems(),
            child: CustomScrollView(
              slivers: [
                if (hasItems(trashViewModel))
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Deleted Items',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.delete_forever, color: Colors.red),
                            label: const Text('Empty Trash', style: TextStyle(color: Colors.red)),
                            onPressed: () => _showConfirmEmptyTrash(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (hasNotebooks)
                  SliverToBoxAdapter(
                    child: _buildSectionHeader(context, 'Deleted Notebooks'),
                  ),
                if (hasNotebooks)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildNotebookItem(
                        context, trashViewModel.trashedNotebooks[index], trashViewModel),
                      childCount: trashViewModel.trashedNotebooks.length,
                    ),
                  ),
                if (hasNotes)
                  SliverToBoxAdapter(
                    child: _buildSectionHeader(context, 'Deleted Notes'),
                  ),
                if (hasNotes)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildNoteItem(
                        context, trashViewModel.trashedNotes[index], trashViewModel),
                      childCount: trashViewModel.trashedNotes.length,
                    ),
                  ),
                // Add some bottom padding
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
          );
        },
      ),
    );
  }

  bool hasItems(TrashViewModel trashViewModel) {
    return trashViewModel.trashedNotes.isNotEmpty || trashViewModel.trashedNotebooks.isNotEmpty;
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildNoteItem(BuildContext context, Note note, TrashViewModel trashViewModel) {
    final deletedOn = formatDate(note.deletedAt);
    
    return CardContainer(
      title: note.title,
      subtitle: 'Deleted on $deletedOn',
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.description_outlined,
          color: Theme.of(context).primaryColor,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.restore, color: Colors.green),
            onPressed: () => _restoreItem(context, 'note', note.id, note.title, trashViewModel),
            tooltip: 'Restore',
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            onPressed: () => _showDeleteForeverDialog(
              context, 'note', note.id, note.title, trashViewModel),
            tooltip: 'Delete permanently',
          ),
        ],
      ),
    );
  }

  Widget _buildNotebookItem(BuildContext context, Notebook notebook, TrashViewModel trashViewModel) {
    final deletedOn = formatDate(notebook.deletedAt);
    
    return CardContainer(
      title: notebook.name,
      subtitle: 'Deleted on $deletedOn',
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.folder_outlined,
          color: Theme.of(context).primaryColor,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.restore, color: Colors.green),
            onPressed: () => _restoreItem(context, 'notebook', notebook.id, notebook.name, trashViewModel),
            tooltip: 'Restore',
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            onPressed: () => _showDeleteForeverDialog(
              context, 'notebook', notebook.id, notebook.name, trashViewModel),
            tooltip: 'Delete permanently',
          ),
        ],
      ),
    );
  }

  String formatDate(DateTime? date) {
    if (date == null) return 'Unknown date';
    
    return DateFormat.yMMMMd().add_jm().format(date);
  }

  Future<void> _restoreItem(
      BuildContext context, String type, String id, String name, TrashViewModel trashViewModel) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restoring $name...')),
      );
      
      await trashViewModel.restoreItem(type, id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name restored successfully')),
        );
      }
    } catch (e) {
      _logger.error('Error restoring item', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error restoring item: ${e.toString()}')),
        );
      }
    }
  }

  void _showDeleteForeverDialog(
      BuildContext context, String type, String id, String name, TrashViewModel trashViewModel) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          'This will permanently delete "$name". This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await trashViewModel.permanentlyDeleteItem(type, id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$name permanently deleted')),
                  );
                }
              } catch (e) {
                _logger.error('Error deleting item permanently', e);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting item: ${e.toString()}'),
                    ),
                  );
                }
              }
            },
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  void _showConfirmEmptyTrash(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty Trash?'),
        content: const Text(
          'This will permanently delete all items in the trash. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await _trashViewModel.emptyTrash();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Trash emptied successfully')),
                  );
                }
              } catch (e) {
                _logger.error('Error emptying trash', e);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error emptying trash: ${e.toString()}'),
                    ),
                  );
                }
              }
            },
            child: const Text('Empty Trash'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Deactivate TrashViewModel when screen is disposed
    if (_isInitialized) {
      _trashViewModel.deactivate();
    }
    super.dispose();
  }
}
