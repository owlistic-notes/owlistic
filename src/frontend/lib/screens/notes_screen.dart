import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../widgets/app_drawer.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../providers/websocket_provider.dart';
import '../utils/provider_extensions.dart';
import 'note_editor_screen.dart';

/// NotesScreen acts as the View in MVP pattern
class NotesScreen extends StatefulWidget {
  @override
  _NotesScreenState createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isInitialized = false;
  int _currentPage = 1;
  bool _hasMoreData = true;
  bool _isLoadingMore = false;
  Set<String> _loadedNoteIds = {}; // Track loaded note IDs to prevent duplicates
  
  // NotesProvider acts as the Presenter
  late NotesProvider _presenter;
  
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
      
      // Get presenters
      _presenter = context.notesPresenter();
      
      // Initialize WebSocket and fetch data
      _initializeData();
    }
  }
  
  Future<void> _initializeData() async {
    final wsProvider = context.webSocketProvider();
    
    // Ensure WebSocket is connected 
    await wsProvider.ensureConnected();
    
    // Register a custom handler for note creation events
    wsProvider.addEventListener('event', 'note.created', (message) {
      try {
        // Extract note ID from the message
        final noteId = message['payload']?['data']?['note_id'] ?? 
                      message['payload']?['data']?['id'];
        
        if (noteId != null) {
          // Process just this note instead of refreshing everything
          _handleNewNote(noteId.toString());
        }
      } catch (e) {
        print('Error handling note creation in UI: $e');
      }
    });
    
    // Subscribe to events
    wsProvider.subscribe('note');
    
    // Activate the presenter
    _presenter.activate();
    
    // Fetch initial data
    await _presenter.fetchNotes();
    
    // Initialize loaded note IDs
    _updateLoadedNoteIds();
  }
  
  // Update loaded note IDs to track what we've already loaded
  void _updateLoadedNoteIds() {
    setState(() {
      _loadedNoteIds = _presenter.notes.map((note) => note.id).toSet();
    });
  }
  
  // Process a single new note from WebSocket without full refresh
  void _handleNewNote(String noteId) {
    // Check if this note is already loaded
    if (_loadedNoteIds.contains(noteId)) {
      print('NotesScreen: Note $noteId already loaded, skipping');
      return;
    }
    
    print('NotesScreen: Adding new note $noteId from WebSocket event');
    
    // Fetch just this one note and add it to the list
    _presenter.fetchNoteFromEvent(noteId).then((_) {
      // Update our tracking set
      _updateLoadedNoteIds();
    });
  }
  
  // Scroll listener for infinite scrolling
  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoadingMore && _hasMoreData) {
      _loadMoreNotes();
    }
  }
  
  // Load more notes for pagination
  Future<void> _loadMoreNotes() async {
    if (_isLoadingMore) return;
    
    setState(() {
      _isLoadingMore = true;
    });
    
    _currentPage++;
    final currentCount = _presenter.notes.length;
    final currentIds = _presenter.notes.map((note) => note.id).toSet();
    
    // Pass the currently loaded IDs to avoid fetching duplicates
    await _presenter.fetchNotes(
      page: _currentPage, 
      excludeIds: currentIds.toList(),
    );
    
    // Check if we got new data
    final hasNewData = _presenter.notes.length > currentCount;
    
    setState(() {
      _hasMoreData = hasNewData;
      _isLoadingMore = false;
    });
  }

  void _showAddNoteDialog() {
    final _titleController = TextEditingController();
    String? selectedNotebookId;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ... notebook dropdown controls...
            TextField(
              controller: _titleController,
              decoration: InputDecoration(labelText: 'Title'),
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
              if (_titleController.text.isNotEmpty && selectedNotebookId != null) {
                Navigator.of(ctx).pop();
                await _presenter.createNote(selectedNotebookId!, _titleController.text);
              }
            },
            child: Text('Add'),
          ),
        ],
      ),
    );
  }

  void _navigateToNoteEditor(Note note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NoteEditorScreen(note: note),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to presenters for updates
    final wsProvider = context.webSocketProvider(listen: true);
    final notesPresenter = context.notesPresenter(listen: true);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Notes'),
        actions: [
          // Add refresh button
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              notesPresenter.fetchNotes();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Refreshing notes...'))
              );
            },
            tooltip: 'Refresh notes',
          ),
          // Connection indicator
          IconButton(
            icon: Icon(
              wsProvider.isConnected ? Icons.wifi : Icons.wifi_off,
              color: wsProvider.isConnected ? Colors.green : Colors.red,
            ),
            onPressed: () {
              wsProvider.reconnect().then((_) {
                notesPresenter.fetchNotes();
              });
            },
            tooltip: 'WebSocket status - click to reconnect',
          ),
        ],
      ),
      drawer: AppDrawer(),
      body: _buildBody(notesPresenter),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddNoteDialog,
        child: Icon(Icons.add),
      ),
    );
  }
  
  Widget _buildBody(NotesProvider presenter) {
    if (presenter.isLoading && presenter.notes.isEmpty) {
      return Center(child: CircularProgressIndicator());
    }
    
    if (presenter.notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('No notes found'),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => presenter.fetchNotes(),
              child: Text('Refresh'),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      controller: _scrollController,
      itemCount: presenter.notes.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        // Show loading indicator at the end
        if (index == presenter.notes.length) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        
        final note = presenter.notes[index];
        return Card(
          key: ValueKey('note_${note.id}'), // Ensure stable identity with key
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Text(note.title),
            subtitle: Text(note.content),
            leading: Icon(Icons.note),
            onTap: () => _navigateToNoteEditor(note),
            trailing: IconButton(
              icon: Icon(Icons.delete),
              onPressed: () => presenter.deleteNote(note.id),
            ),
          ),
        );
      },
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
