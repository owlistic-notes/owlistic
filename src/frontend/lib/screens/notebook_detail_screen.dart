import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note.dart';
import '../providers/notebooks_provider.dart';
import '../providers/websocket_provider.dart';
import '../utils/provider_extensions.dart';
import 'note_editor_screen.dart';

/// NotebookDetailScreen acts as the View in MVP pattern
class NotebookDetailScreen extends StatefulWidget {
  final String notebookId;

  const NotebookDetailScreen({Key? key, required this.notebookId}) : super(key: key);

  @override
  _NotebookDetailScreenState createState() => _NotebookDetailScreenState();
}

class _NotebookDetailScreenState extends State<NotebookDetailScreen> {
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
    
    // Subscribe to the notebook and notes
    _webSocketProvider.subscribe('notebook', id: widget.notebookId);
    _webSocketProvider.subscribe('notebook:notes', id: widget.notebookId);
    _webSocketProvider.subscribe('note');
    
    // Fetch notebook data
    await _presenter.fetchNotebookById(widget.notebookId);
  }

  void _showAddNoteDialog(BuildContext context, String notebookId) {
    final _titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Note'),
        content: TextField(
          controller: _titleController,
          decoration: InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_titleController.text.isNotEmpty) {
                try {
                  await _presenter.addNoteToNotebook(notebookId, _titleController.text);
                  Navigator.of(ctx).pop();
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to create note')),
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
    // Listen to websocket provider for connection status
    final wsProvider = context.webSocketProvider(listen: true);
    
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
      key: ValueKey('notebook_${widget.notebookId}'),
      appBar: AppBar(
        title: Text(hasNotebook ? notebook!.name : 'Notebook Details'),
        actions: [
          // Add refresh button
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              notebooksPresenter.fetchNotebookById(widget.notebookId);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Refreshing notebook...'))
              );
            },
          ),
          // Connection indicator
          Tooltip(
            message: 'WebSocket ${wsProvider.isConnected ? "Connected" : "Disconnected"}',
            child: Icon(
              wsProvider.isConnected ? Icons.wifi : Icons.wifi_off,
              color: wsProvider.isConnected ? Colors.green : Colors.red,
            ),
          ),
          SizedBox(width: 16),
        ],
      ),
      body: !hasNotebook
          ? Center(child: CircularProgressIndicator())
          : _buildNotebookContent(notebook!),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddNoteDialog(context, widget.notebookId),
        child: Icon(Icons.add),
      ),
    );
  }
  
  Widget _buildNotebookContent(dynamic notebook) {
    if (notebook.notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('No notes in this notebook'),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _showAddNoteDialog(context, widget.notebookId),
              child: Text('Add Note'),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      key: ValueKey('notes_list_${notebook.notes.length}'),
      itemCount: notebook.notes.length,
      itemBuilder: (context, index) {
        final note = notebook.notes[index];
        return Card(
          key: ValueKey('note_${note.id}'),
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Text(note.title),
            subtitle: Text(note.blocks.isNotEmpty ? note.blocks.first.content : ''),
            leading: Icon(Icons.note),
            onTap: () => _navigateToNoteEditor(context, note),
            trailing: IconButton(
              icon: Icon(Icons.delete),
              onPressed: () async {
                try {
                  await _presenter.deleteNoteFromNotebook(
                      widget.notebookId, note.id);
                } catch (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete note')),
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }
  
  @override
  void dispose() {
    // Unsubscribe and deactivate when the view is disposed
    if (_isInitialized) {
      _webSocketProvider.unsubscribe('notebook', id: widget.notebookId);
      _webSocketProvider.unsubscribe('notebook:notes', id: widget.notebookId);
      
      // Deactivate the presenter
      _presenter.deactivate();
    }
    
    super.dispose();
  }
}
