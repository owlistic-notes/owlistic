import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../models/notebook.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'websocket_provider.dart';
import '../models/subscription.dart';
import '../utils/debug_utils.dart';
import '../utils/websocket_message_parser.dart';

class NotebooksProvider with ChangeNotifier {
  List<Notebook> _notebooks = [];
  bool _isLoading = false;
  final WebSocketService _webSocketService = WebSocketService();
  WebSocketProvider? _webSocketProvider;
  bool _initialized = false;

  List<Notebook> get notebooks => [..._notebooks];
  bool get isLoading => _isLoading;

  NotebooksProvider() {
    // Initialize WebSocket connection
    _webSocketService.connect();
    print('NotebooksProvider initialized');
  }
  
  // Called by ProxyProvider in main.dart
  void initialize(WebSocketProvider webSocketProvider) {
    if (_initialized) return;
    _initialized = true;
    
    _webSocketProvider = webSocketProvider;
    _registerEventHandlers();
    
    print('NotebooksProvider registered event handlers');
  }
  
  void setWebSocketProvider(WebSocketProvider provider) {
    // Skip if the provider is the same
    if (_webSocketProvider == provider) return;
    
    // Unregister from old provider if exists
    if (_webSocketProvider != null) {
      _unregisterEventHandlers();
    }
    
    _webSocketProvider = provider;
    
    // Register event handlers
    _registerEventHandlers();
  }
  
  void _registerEventHandlers() {
    // Register handlers for all relevant event types
    _webSocketProvider?.addEventListener('event', 'notebook.updated', _handleNotebookUpdate);
    _webSocketProvider?.addEventListener('event', 'notebook.created', _handleNotebookCreate);
    _webSocketProvider?.addEventListener('event', 'notebook.deleted', _handleNotebookDelete);
    _webSocketProvider?.addEventListener('event', 'note.created', _handleNoteCreate);
    _webSocketProvider?.addEventListener('event', 'note.deleted', _handleNoteDelete);
    
    print('NotebooksProvider: Event handlers registered');
  }
  
  void _unregisterEventHandlers() {
    _webSocketProvider?.removeEventListener('event', 'notebook.updated');
    _webSocketProvider?.removeEventListener('event', 'notebook.created');
    _webSocketProvider?.removeEventListener('event', 'notebook.deleted');
    _webSocketProvider?.removeEventListener('event', 'note.created');
    _webSocketProvider?.removeEventListener('event', 'note.deleted');
  }

  void _handleNotebookUpdate(Map<String, dynamic> message) {
    // Get notebook ID from payload
    if (message.containsKey('payload') && 
        message['payload'] is Map<String, dynamic> &&
        message['payload']['data'] is Map<String, dynamic>) {
        
      final data = message['payload']['data'];
      final notebookId = data['notebook_id'];
      
      if (notebookId != null) {
        // Fetch updated notebook data from server
        _fetchSingleNotebook(notebookId.toString());
      }
    }
  }
  
  void _handleNotebookCreate(Map<String, dynamic> message) {
    // Get notebook ID from payload
    if (message.containsKey('payload') && 
        message['payload'] is Map<String, dynamic> &&
        message['payload']['data'] is Map<String, dynamic>) {
        
      final data = message['payload']['data'];
      final notebookId = data['notebook_id'];
      
      if (notebookId != null) {
        // Add a delay before fetching to ensure database is updated
        Future.delayed(Duration(milliseconds: 500), () {
          _fetchSingleNotebook(notebookId.toString());
        });
      }
    }
  }
  
  // Fetch a single notebook
  Future<Notebook> _fetchSingleNotebook(String notebookId) async {
    print('NotebooksProvider: Fetching single notebook: $notebookId');
    try {
      // Use ApiService to fetch the notebook by ID
      final notebook = await ApiService.getNotebook(notebookId);
      
      print('NotebooksProvider: Fetched notebook ${notebook.id} with ${notebook.notes.length} notes');
      
      // Check if notebook exists in our list
      final index = _notebooks.indexWhere((nb) => nb.id == notebookId);
      if (index != -1) {
        _notebooks[index] = notebook;
        print('NotebooksProvider: Updated existing notebook: $notebookId with ${notebook.notes.length} notes');
      } else {
        _notebooks.add(notebook);
        print('NotebooksProvider: Added new notebook: $notebookId with ${notebook.notes.length} notes');
        
        // Subscribe to this notebook
        if (_webSocketProvider != null) {
          _webSocketProvider!.subscribe('notebook', id: notebook.id);
          _webSocketProvider!.subscribe('notebook:notes', id: notebook.id);
        }
      }
      
      // Notify listeners immediately
      notifyListeners();
      
      return notebook;
    } catch (error) {
      print('NotebooksProvider: Error fetching notebook: $error');
      throw error;
    }
  }

  // Public method to fetch a single notebook by ID
  Future<Notebook?> fetchNotebookById(String notebookId) async {
    try {
      final notebook = await _fetchSingleNotebook(notebookId);
      return notebook;
    } catch (error) {
      print('NotebooksProvider: Error in fetchNotebookById: $error');
      return null;
    }
  }
  
  void _handleNotebookDelete(Map<String, dynamic> payload) {
    final data = payload['data'];
    final String notebookId = _extractNotebookId(data);
    
    if (notebookId.isNotEmpty) {
      // Remove notebook from local state if it exists
      _notebooks.removeWhere((notebook) => notebook.id == notebookId);
      notifyListeners();
    }
  }
  
  // More robust handling of note creation events with immediate UI update
  void _handleNoteCreate(Map<String, dynamic> message) {
    print('NotebooksProvider: Received note.created event');
    
    try {
      // Parse message using the new parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      
      // Extract note_id and notebook_id using the extractor
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      final String? notebookId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
      
      print('NotebooksProvider: Extracted from event: noteId=$noteId, notebookId=$notebookId');
      
      // If we have a notebook ID, refresh it
      if (notebookId != null) {
        print('NotebooksProvider: Will refresh notebook $notebookId from note.created event');
        _refreshNotebookWithNote(notebookId);
        return;
      }
      
      // If we only have a note ID, fetch the note to get its notebook
      if (noteId != null) {
        print('NotebooksProvider: Attempting to fetch note $noteId to find its notebook');
        
        ApiService.getNote(noteId).then((note) {
          print('NotebooksProvider: Found note belongs to notebook ${note.notebookId}');
          _refreshNotebookWithNote(note.notebookId);
        }).catchError((e) {
          print('NotebooksProvider: Failed to fetch note details: $e');
        });
        return;
      }

      print('NotebooksProvider: Not enough information to process note creation');
    } catch (e) {
      print('NotebooksProvider: Error handling note create: $e');
    }
  }
  
  // Helper method to refresh a notebook with new note data
  void _refreshNotebookWithNote(String notebookId) {
    print('NotebooksProvider: Will refresh notebook $notebookId');
    
    // Check if this notebook is in our local state
    final notebookIndex = _notebooks.indexWhere((nb) => nb.id == notebookId);
    
    // Add a delay to allow database to complete the transaction
    Future.delayed(Duration(milliseconds: 2000), () {
      print('NotebooksProvider: Attempting to fetch notebook $notebookId after delay');
      _fetchSingleNotebook(notebookId);
    });
  }
  
  void _handleNoteDelete(Map<String, dynamic> payload) {
    final data = payload['data'];
    final String notebookId = data['notebook_id'] != null ? data['notebook_id'].toString() : '';
    final String noteId = data['note_id'] != null ? data['note_id'].toString() : 
                         (data['id'] != null ? data['id'].toString() : '');
    
    if (notebookId.isNotEmpty && noteId.isNotEmpty) {
      // If this notebook is in our list, update it
      final int index = _notebooks.indexWhere((notebook) => notebook.id == notebookId);
      if (index != -1) {
        // Remove the note from local state
        final currentNotebook = _notebooks[index];
        final updatedNotes = currentNotebook.notes.where((note) => note.id != noteId).toList();
        
        _notebooks[index] = Notebook(
          id: currentNotebook.id,
          name: currentNotebook.name,
          description: currentNotebook.description,
          userId: currentNotebook.userId,
          notes: updatedNotes,
        );
        
        notifyListeners();
      }
    }
  }
  
  // More robust extraction of notebook ID
  String _extractNotebookId(dynamic data) {
    if (data == null) return '';
    
    String notebookId = '';
    if (data is Map<String, dynamic>) {
      if (data['notebook_id'] != null) {
        notebookId = data['notebook_id'].toString();
      } else if (data['id'] != null && 
                (data['name'] != null || 
                 data['description'] != null || 
                 data['entity'] == 'notebook' || 
                 data['resource'] == 'notebook')) {
        notebookId = data['id'].toString();
      }
    }
    
    return notebookId;
  }
  
  // Fetch notebooks and subscribe to them with more reliable subscriptions and pagination
  Future<void> fetchNotebooks({int page = 1, int pageSize = 20}) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Fetch notebooks with pagination
      final fetchedNotebooks = await ApiService.fetchNotebooks(page: page, pageSize: pageSize);
      
      if (page == 1) {
        // First page, replace existing data
        _notebooks = fetchedNotebooks;
      } else {
        // Subsequent page, append to existing data
        _notebooks.addAll(fetchedNotebooks);
      }
      
      // Subscribe using batches for better performance
      if (_webSocketProvider != null) {
        // Prepare base subscriptions
        final subscriptions = <Subscription>[
          Subscription('notebook'),
          Subscription('notebooks'),
          Subscription('note')
        ];
        
        // Add individual notebook subscriptions (limit to avoid overwhelming)
        for (var i = 0; i < _notebooks.length && i < 20; i++) {
          subscriptions.add(Subscription('notebook', id: _notebooks[i].id));
          subscriptions.add(Subscription('notebook:notes', id: _notebooks[i].id));
        }
        
        // Batch subscribe
        await _webSocketProvider!.batchSubscribe(subscriptions);
      } else {
        print('NotebooksProvider: Warning - WebSocket provider not set, cannot subscribe to events');
      }
      
      print('NotebooksProvider: Fetched ${fetchedNotebooks.length} notebooks (page $page)');
    } catch (error) {
      print('Error fetching notebooks: $error');
      // Only clear on first page error
      if (page == 1) _notebooks = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> createNotebook(String name, String description) async {
    try {
      final notebook = await ApiService.createNotebook(name, description);
      _notebooks.add(notebook);
      
      // Subscribe to this notebook
      _webSocketService.subscribe('notebook', id: notebook.id);
      
      notifyListeners();
    } catch (error) {
      print('Error creating notebook: $error');
      rethrow;
    }
  }

  Future<void> addNoteToNotebook(String notebookId, String title) async {
    try {
      final note = await ApiService.createNote(notebookId, title);
      final index = _notebooks.indexWhere((nb) => nb.id == notebookId);
      if (index != -1) {
        final updatedNotebook = _notebooks[index];
        final notes = List<Note>.from(updatedNotebook.notes)..add(note);
        _notebooks[index] = Notebook(
          id: updatedNotebook.id,
          name: updatedNotebook.name,
          description: updatedNotebook.description,
          userId: updatedNotebook.userId,
          notes: notes,
        );
        notifyListeners();
      }
    } catch (error) {
      print('Error adding note to notebook: $error');
      rethrow;
    }
  }

  Future<void> deleteNoteFromNotebook(String notebookId, String noteId) async {
    try {
      await ApiService.deleteNoteFromNotebook(notebookId, noteId);
      final index = _notebooks.indexWhere((nb) => nb.id == notebookId);
      if (index != -1) {
        final updatedNotebook = _notebooks[index];
        final notes = updatedNotebook.notes.where((note) => note.id != noteId).toList();
        _notebooks[index] = Notebook(
          id: updatedNotebook.id,
          name: updatedNotebook.name,
          description: updatedNotebook.description,
          userId: updatedNotebook.userId,
          notes: notes,
        );
        notifyListeners();
      }
    } catch (error) {
      print('Error deleting note from notebook: $error');
      rethrow;
    }
  }

  Future<void> updateNotebook(String id, String name, String description) async {
    try {
      final notebook = await ApiService.updateNotebook(id, name, description);
      final index = _notebooks.indexWhere((nb) => nb.id == id);
      if (index != -1) {
        _notebooks[index] = notebook;
        notifyListeners();
      }
    } catch (error) {
      print('Error updating notebook: $error');
      rethrow;
    }
  }

  Future<void> deleteNotebook(String id) async {
    try {
      await ApiService.deleteNotebook(id);
      _notebooks.removeWhere((notebook) => notebook.id == id);
      
      // Unsubscribe from this notebook
      _webSocketService.unsubscribe('notebook', id: id);
      
      notifyListeners();
    } catch (error) {
      print('Error deleting notebook: $error');
      rethrow;
    }
  }
  
  @override
  void dispose() {
    _unregisterEventHandlers();
    super.dispose();
  }
}
