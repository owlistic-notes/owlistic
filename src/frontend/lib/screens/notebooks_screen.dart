import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../widgets/app_drawer.dart';
import '../providers/notebooks_provider.dart';
import '../providers/websocket_provider.dart';
import '../utils/provider_extensions.dart';

/// NotebooksScreen acts as the View in MVP pattern
class NotebooksScreen extends StatefulWidget {
  @override
  _NotebooksScreenState createState() => _NotebooksScreenState();
}

class _NotebooksScreenState extends State<NotebooksScreen> {
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  bool _isInitialized = false;
  
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
    
    // Activate the presenter
    _presenter.activate();
    
    // Then fetch notebooks
    await _presenter.fetchNotebooks();
    
    // Subscribe to events
    wsProvider.subscribe('notebook');
    wsProvider.subscribe('note');
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
    
    await _presenter.fetchNotebooks(page: _currentPage);
    
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
        title: Text('Add Notebook'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_nameController.text.isNotEmpty) {
                try {
                  await _presenter.createNotebook(_nameController.text, _descriptionController.text);
                  Navigator.of(ctx).pop();
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to create notebook')),
                  );
                }
              }
            },
            child: Text('Add'),
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
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Notebooks'),
        actions: [
          // Add refresh button
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              notebooksPresenter.fetchNotebooks();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Refreshing notebooks...'))
              );
            },
            tooltip: 'Refresh notebooks',
          ),
          // Connection indicator
          IconButton(
            icon: Icon(
              wsProvider.isConnected ? Icons.wifi : Icons.wifi_off,
              color: wsProvider.isConnected ? Colors.green : Colors.red,
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
      drawer: AppDrawer(),
      body: _buildBody(notebooksPresenter),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddNotebookDialog,
        child: Icon(Icons.add),
      ),
    );
  }
  
  Widget _buildBody(NotebooksProvider presenter) {
    if (presenter.isLoading && _currentPage == 1) {
      return Center(child: CircularProgressIndicator());
    }

    return presenter.notebooks.isEmpty
        ? Center(child: Text('No notebooks found'))
        : Stack(
            children: [
              ListView.builder(
                controller: _scrollController,
                itemCount: presenter.notebooks.length + (_isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  // Show loading indicator at the end
                  if (index == presenter.notebooks.length) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  
                  final notebook = presenter.notebooks[index];
                  return Card(
                    margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      title: Text(notebook.name),
                      subtitle: Text(notebook.description),
                      leading: Icon(Icons.book),
                      onTap: () => context.go('/notebooks/${notebook.id}'),
                    ),
                  );
                },
              ),
            ],
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
