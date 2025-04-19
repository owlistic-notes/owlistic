import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/app_drawer.dart';
import '../widgets/card_container.dart';
import '../widgets/empty_state.dart';
import '../providers/notebooks_provider.dart';
import '../utils/provider_extensions.dart';
import '../utils/logger.dart';
import '../core/theme.dart';

/// NotebooksScreen acts as the View in MVP pattern
class NotebooksScreen extends StatefulWidget {
  @override
  _NotebooksScreenState createState() => _NotebooksScreenState();
}

class _NotebooksScreenState extends State<NotebooksScreen> {
  final Logger _logger = Logger('NotebooksScreen');
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  bool _isInitialized = false;
  Set<String> _loadedNotebookIds = {}; // Track loaded notebook IDs
  
  // NotebooksProvider acts as the Presenter
  late NotebooksProvider _presenter;
  
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
      
      // Get the presenter
      _presenter = context.notebooksPresenter();
      
      // Initialize data
      _initializeData();
    }
  }
  
  Future<void> _initializeData() async {
    final wsProvider = context.webSocketProvider();
    
    // Ensure WebSocket is connected first
    await wsProvider.ensureConnected();
    
    // Register a custom handler for notebook creation events
    wsProvider.addEventListener('event', 'notebook.created', (message) {
      try {
        // Extract notebook ID from the message
        final notebookId = message['payload']?['data']?['notebook_id'] ?? 
                          message['payload']?['data']?['id'];
        
        if (notebookId != null) {
          // Process just this notebook instead of refreshing everything
          _handleNewNotebook(notebookId.toString());
        }
      } catch (e) {
        _logger.error('Error handling notebook creation in UI', e);
      }
    });
    
    // Activate the presenter
    _presenter.activate();
    
    // Then fetch notebooks
    await _presenter.fetchNotebooks();
    
    // Initialize loaded notebook IDs
    _updateLoadedIds();
    
    // Subscribe to events
    wsProvider.subscribe('notebook');
    wsProvider.subscribe('note');
  }
  
  // Update the set of loaded IDs
  void _updateLoadedIds() {
    setState(() {
      _loadedNotebookIds = _presenter.notebooks.map((nb) => nb.id).toSet();
    });
  }
  
  // Process a single new notebook from WebSocket without full refresh
  void _handleNewNotebook(String notebookId) {
    // Check if this notebook is already loaded
    if (_loadedNotebookIds.contains(notebookId)) {
      _logger.debug('Notebook $notebookId already loaded, skipping');
      return;
    }
    
    _logger.info('Adding new notebook $notebookId from WebSocket event');
    
    // Fetch just this one notebook and add it to the list
    _presenter.fetchNotebookById(notebookId).then((_) {
      // Update our tracking set
      _updateLoadedIds();
    });
  }
  
  // Scroll listener for infinite scrolling
  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoadingMore && _hasMoreData) {
      _loadMoreData();
    }
  }
  
  // Load next page of data
  Future<void> _loadMoreData() async {
    if (_isLoadingMore) return;
    
    setState(() {
      _isLoadingMore = true;
    });
    
    _currentPage++;
    
    // Get current notebook count to compare after fetch
    final currentCount = _presenter.notebooks.length;
    final currentIds = _presenter.notebooks.map((nb) => nb.id).toSet();
    
    // Pass currently loaded IDs to avoid duplicates
    await _presenter.fetchNotebooks(
      page: _currentPage,
      pageSize: 20,
      excludeIds: currentIds.toList(),
    );
    
    // Check if we got new data
    _hasMoreData = _presenter.notebooks.length > currentCount;
    
    setState(() {
      _isLoadingMore = false;
    });
  }

  void _showAddNotebookDialog() {
    final _nameController = TextEditingController();
    final _descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.folder, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            const Text('Add Notebook'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.drive_file_rename_outline),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                prefixIcon: Icon(Icons.subject),
              ),
              maxLines: 3,
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
              if (_nameController.text.isNotEmpty) {
                try {
                  await _presenter.createNotebook(_nameController.text, _descriptionController.text);
                  Navigator.of(ctx).pop();
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to create notebook')),
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

  @override
  Widget build(BuildContext context) {
    // Listen to websocket provider for connection status
    final wsProvider = context.webSocketProvider(listen: true);
    
    // Listen to notebooks provider for data updates
    final notebooksPresenter = context.notebooksPresenter(listen: true);
    
    // Add key based on notebook count to force rebuild when notebooks change
    final notebookCount = notebooksPresenter.notebooks.length;
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Notebooks'),
        actions: [
          // Add refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              notebooksPresenter.fetchNotebooks();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Refreshing notebooks...'))
              );
            },
            tooltip: 'Refresh notebooks',
          ),
          // Connection indicator
          IconButton(
            icon: Icon(
              wsProvider.isConnected ? Icons.wifi : Icons.wifi_off,
              color: wsProvider.isConnected ? Colors.white : Colors.white70,
            ),
            onPressed: () {
              // Use regular reconnect method and then refresh notebooks
              wsProvider.reconnect().then((_) {
                // Re-fetch notebooks after reconnect
                Future.microtask(() {
                  notebooksPresenter.fetchNotebooks();
                });
              });
            },
            tooltip: 'WebSocket status - click to reconnect',
          )
        ],
      ),
      drawer: const AppDrawer(),
      body: _buildBody(notebooksPresenter),
      key: ValueKey('notebooks_screen_$notebookCount'),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddNotebookDialog,
        child: const Icon(Icons.add),
        tooltip: 'Add Notebook',
      ),
    );
  }
  
  Widget _buildBody(NotebooksProvider presenter) {
    if (presenter.isLoading && _currentPage == 1) {
      return const Center(child: CircularProgressIndicator());
    }

    if (presenter.notebooks.isEmpty) {
      return EmptyState(
        title: 'No notebooks found',
        message: 'Create your first notebook to get started',
        icon: Icons.folder_outlined,
        onAction: _showAddNotebookDialog,
        actionLabel: 'Create Notebook',
      );
    }

    return RefreshIndicator(
      onRefresh: () => presenter.fetchNotebooks(),
      color: Theme.of(context).primaryColor,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: presenter.notebooks.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          // Show loading indicator at the end
          if (index == presenter.notebooks.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          
          final notebook = presenter.notebooks[index];
          return CardContainer(
            key: ValueKey('notebook_${notebook.id}'),
            onTap: () => context.go('/notebooks/${notebook.id}'),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.folder,
                color: Theme.of(context).primaryColor,
                size: 24,
              ),
            ),
            title: notebook.name,
            subtitle: '${notebook.notes.length} notes',
            trailing: Icon(Icons.chevron_right, color: Theme.of(context).iconTheme.color),
            child: notebook.description.isEmpty
                ? const SizedBox.shrink()
                : Text(
                    notebook.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
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
    
    // Deactivate the presenter when the view is disposed
    _presenter.deactivate();
    
    super.dispose();
  }
}
