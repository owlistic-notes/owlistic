import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note.dart';
import '../models/notebook.dart';
import '../providers/trash_provider.dart';
import '../providers/websocket_provider.dart';
import '../utils/provider_extensions.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_bar_common.dart';
import '../widgets/card_container.dart';
import '../widgets/empty_state.dart';
import '../core/theme.dart';
import '../utils/logger.dart'; // Added logger import
import 'package:intl/intl.dart'; // For date formatting

class TrashScreen extends StatefulWidget {
  @override
  _TrashScreenState createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;
  bool _isInitialized = false;
  final Logger _logger = Logger('TrashScreen'); // Added logger instance
  
  // Presenters
  late TrashProvider _presenter;
  late WebSocketProvider _wsProvider;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    if (!_isInitialized) {
      _isInitialized = true;
      
      // Get presenters
      _presenter = Provider.of<TrashProvider>(context, listen: false);
      _wsProvider = context.webSocketProvider();
      
      // Initialize
      _initializeData();
    }
  }
  
  Future<void> _initializeData() async {
    // Ensure WebSocket is connected
    await _wsProvider.ensureConnected();
    
    // Register event handlers for trash updates
    _wsProvider.addEventListener('event', 'trash.restored', (message) {
      _refreshTrash();
    });
    
    _wsProvider.addEventListener('event', 'trash.deleted', (message) {
      _refreshTrash();
    });
    
    // Set WebSocket provider and activate
    _presenter.setWebSocketProvider(_wsProvider);
    _presenter.activate();
    
    // Initial fetch
    await _presenter.fetchTrashedItems();
  }
  
  Future<void> _refreshTrash() async {
    if (!mounted) return;
    
    try {
      await _presenter.fetchTrashedItems();
      setState(() {});
    } catch (e) {
      _logger.error('Error refreshing trash items', e);
    }
  }
  
  void _showEmptyTrashConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty Trash'),
        content: const Text(
          'All items in the trash will be permanently deleted. This action cannot be undone. Are you sure?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await _presenter.emptyTrash();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Trash emptied successfully')),
                );
              } catch (error) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to empty trash')),
                );
              }
            },
            style: AppTheme.getDangerButtonStyle(),
            child: const Text('Empty Trash'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBarCommon(
        title: 'Trash',
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
        additionalActions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Empty trash',
            onPressed: () => _showEmptyTrashConfirmation(),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: _buildBody(),
    );
  }
  
  Widget _buildBody() {
    return Consumer<TrashProvider>(
      builder: (context, trashProvider, _) {
        if (trashProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final hasNotes = trashProvider.trashedNotes.isNotEmpty;
        final hasNotebooks = trashProvider.trashedNotebooks.isNotEmpty;
        
        if (!hasNotes && !hasNotebooks) {
          return const EmptyState(
            title: 'Trash is Empty',
            message: 'Items you delete will appear here for 30 days before being permanently deleted',
            icon: Icons.delete_outline,
          );
        }
        
        return Column(
          children: [
            TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color,
              tabs: [
                Tab(
                  icon: const Icon(Icons.description_outlined),
                  text: 'Notes (${trashProvider.trashedNotes.length})',
                ),
                Tab(
                  icon: const Icon(Icons.folder_outlined),
                  text: 'Notebooks (${trashProvider.trashedNotebooks.length})',
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Notes Tab
                  _buildNotesTab(trashProvider),
                  
                  // Notebooks Tab
                  _buildNotebooksTab(trashProvider),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
  
  Widget _buildNotesTab(TrashProvider trashProvider) {
    final notes = trashProvider.trashedNotes;
    
    if (notes.isEmpty) {
      return const EmptyState(
        title: 'No Notes in Trash',
        message: 'Deleted notes will appear here',
        icon: Icons.description_outlined,
      );
    }
    
    return RefreshIndicator(
      onRefresh: () => trashProvider.fetchTrashedItems(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: notes.length,
        itemBuilder: (context, index) {
          final note = notes[index];
          return _buildTrashedNoteCard(context, note);
        },
      ),
    );
  }
  
  Widget _buildNotebooksTab(TrashProvider trashProvider) {
    final notebooks = trashProvider.trashedNotebooks;
    
    if (notebooks.isEmpty) {
      return const EmptyState(
        title: 'No Notebooks in Trash',
        message: 'Deleted notebooks will appear here',
        icon: Icons.folder_outlined,
      );
    }
    
    return RefreshIndicator(
      onRefresh: () => trashProvider.fetchTrashedItems(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: notebooks.length,
        itemBuilder: (context, index) {
          final notebook = notebooks[index];
          return _buildTrashedNotebookCard(context, notebook);
        },
      ),
    );
  }
  
  Widget _buildTrashedNoteCard(BuildContext context, Note note) {
    // Ensure we handle null deletedAt properly
    final deletedDate = note.deletedAt != null 
      ? 'Deleted on ${_formatDate(note.deletedAt!)}'
      : 'Recently deleted';
    
    // Handle potentially null blocks array
    final noteContent = note.blocks.isNotEmpty 
        ? note.blocks.first.getTextContent() 
        : 'Empty note';
      
    return CardContainer(
      title: note.title,
      subtitle: deletedDate,
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
      child: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.restore),
              label: const Text('Restore'),
              onPressed: () async {
                try {
                  await _presenter.restoreItem('note', note.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Note restored')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to restore note')),
                  );
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever),
              label: const Text('Delete'),
              onPressed: () => _showPermanentDeleteConfirmation(
                context, 'note', note.id, note.title),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.dangerColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTrashedNotebookCard(BuildContext context, Notebook notebook) {
    const deletedDate = 'Deleted recently'; // Default text since Notebook might not have deletedAt
    final noteCount = notebook.notes.length;
    final notesText = noteCount == 1 ? '1 note' : '$noteCount notes';
      
    return CardContainer(
      title: notebook.name,
      subtitle: deletedDate,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.folder_outlined,
          color: Theme.of(context).primaryColor,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (notebook.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  notebook.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Text(
              notesText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore'),
                  onPressed: () async {
                    try {
                      await _presenter.restoreItem('notebook', notebook.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Notebook restored')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to restore notebook')),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Delete'),
                  onPressed: () => _showPermanentDeleteConfirmation(
                    context, 'notebook', notebook.id, notebook.name),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.dangerColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  void _showPermanentDeleteConfirmation(BuildContext context, String type, String id, String name) {
    final typeTitle = type == 'note' ? 'Note' : 'Notebook';
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $typeTitle Permanently'),
        content: Text(
          'Are you sure you want to permanently delete "$name"? This action cannot be undone.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await _presenter.permanentlyDeleteItem(type, id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$typeTitle permanently deleted')),
                );
              } catch (error) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete $typeTitle')),
                );
              }
            },
            style: AppTheme.getDangerButtonStyle(),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }
  
  String _formatDate(DateTime date) {
    // Ensure DateFormat is initialized
    try {
      final DateFormat formatter = DateFormat('MMM dd, yyyy');
      return formatter.format(date);
    } catch (e) {
      return date.toString().substring(0, 10); // Basic fallback
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    
    if (_isInitialized) {
      // Remove event listeners
      _wsProvider.removeEventListener('event', 'trash.restored');
      _wsProvider.removeEventListener('event', 'trash.deleted');
      
      _presenter.deactivate();
    }
    
    super.dispose();
  }
}
