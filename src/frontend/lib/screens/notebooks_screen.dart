import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:thinkstack/utils/websocket_message_parser.dart';
import '../widgets/app_drawer.dart';
import '../widgets/card_container.dart';
import '../widgets/empty_state.dart';
import '../providers/notebooks_provider.dart';
import '../utils/provider_extensions.dart';
import '../utils/logger.dart';
import '../core/theme.dart';
import '../widgets/app_bar_common.dart';

/// NotebooksScreen acts as the View in MVP pattern
class NotebooksScreen extends StatefulWidget {
  @override
  _NotebooksScreenState createState() => _NotebooksScreenState();
}

class _NotebooksScreenState extends State<NotebooksScreen> {
  final Logger _logger = Logger('NotebooksScreen');
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
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
    
    // Replace the previous event handlers with more efficient ones
    wsProvider.addEventListener('event', 'notebook.created', (message) {
      _logger.info('Notebook created event received');
      // Extract notebook ID from message
      try {
        // Use the standardized parser
        final parsedMessage = WebSocketMessage.fromJson(message);
        final String? notebookId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
        
        if (notebookId != null && notebookId.isNotEmpty) {
          // Only fetch the specific notebook without triggering a full refresh
          _refreshNotebookById(notebookId);
        } else {
          _logger.warning('Could not extract notebook_id from message');
        }
      } catch (e) {
        _logger.error('Error handling notebook create event', e);
      }
    });

    wsProvider.addEventListener('event', 'notebook.updated', (message) {
      _logger.info('Notebook updated event received');
      try {
        // Use the standardized parser
        final parsedMessage = WebSocketMessage.fromJson(message);
        final String? notebookId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
        
        if (notebookId != null && notebookId.isNotEmpty) {
          // Only update the specific notebook
          if (_loadedNotebookIds.contains(notebookId)) {
            _refreshNotebookById(notebookId);
          }
        } else {
          _logger.warning('Could not extract notebook_id from message');
        }
      } catch (e) {
        _logger.error('Error handling notebook update event', e);
      }
    });

    wsProvider.addEventListener('event', 'notebook.deleted', (message) {
      _logger.info('Notebook deleted event received');
      try {
        // Use the standardized parser
        final parsedMessage = WebSocketMessage.fromJson(message);
        final String? notebookId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
        
        if (notebookId != null && notebookId.isNotEmpty) {
          // Remove the notebook locally without making a network request
          if (_loadedNotebookIds.contains(notebookId)) {
            _presenter.removeNotebookById(notebookId);
            // Update tracking list
            setState(() {
              _loadedNotebookIds.remove(notebookId);
            });
          }
        } else {
          _logger.warning('Could not extract notebook_id from message');
        }
      } catch (e) {
        _logger.error('Error handling notebook delete event', e);
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

  // Refresh all notebooks data 
  Future<void> _refreshNotebooks() async {
    if (!mounted) return;
    
    try {
      await _presenter.fetchNotebooks();
      _updateLoadedIds();
    } catch (e) {
      _logger.error('Error refreshing notebooks', e);
    }
  }

  // Refresh a specific notebook by ID
  Future<void> _refreshNotebookById(String notebookId) async {
    // Check if this notebook is already loaded
    if (_loadedNotebookIds.contains(notebookId)) {
      _logger.debug('Notebook $notebookId already loaded, updating');
      // Update existing notebook
      _presenter.fetchNotebookById(notebookId).then((_) {
        // Update our tracking set after successful fetch
        if (mounted) setState(() {});
      }).catchError((error) {
        _logger.error('Error updating notebook by id', error);
      });
      return;
    }
    
    _logger.info('Adding new notebook $notebookId from WebSocket event');
    
    // Fetch just this one notebook and add it to the list without refreshing
    _presenter.fetchNotebookById(notebookId).then((_) {
      // Update our tracking set after successful fetch
      if (mounted) {
        setState(() {
          _loadedNotebookIds.add(notebookId);
        });
      }
    }).catchError((error) {
      _logger.error('Error fetching notebook by id', error);
    });
  }

  // Update the set of loaded IDs
  void _updateLoadedIds() {
    setState(() {
      _loadedNotebookIds = _presenter.notebooks.map((nb) => nb.id).toSet();
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

  void _showDeleteConfirmation(BuildContext context, String notebookId, String notebookName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Notebook'),
        content: Text('Are you sure you want to delete "$notebookName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await _presenter.deleteNotebook(notebookId);
              } catch (error) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to delete notebook')),
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
    // Listen to notebooks provider for data updates
    final notebooksPresenter = context.notebooksPresenter(listen: true);
    
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBarCommon(
        title: 'Notebooks',
        onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
        onBackPressed: () {
          if (Navigator.canPop(context)) {
            Navigator.of(context).pop();
          }
        },
      ),
      drawer: const AppDrawer(),
      body: _buildBody(notebooksPresenter),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddNotebookDialog,
        tooltip: 'Add Notebook',
        child: const Icon(Icons.add),
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
      onRefresh: _refreshNotebooks,
      color: Theme.of(context).primaryColor,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            trailing: IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: AppTheme.dangerColor,
              ),
              onPressed: () => _showDeleteConfirmation(
                context, 
                notebook.id, 
                notebook.name,
              ),
            ),
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
