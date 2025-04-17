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
  // Use a Map instead of a List to prevent duplicates
  final Map<String, Notebook> _notebooksMap = {};
  bool _isLoading = false;
  final WebSocketService _webSocketService = WebSocketService();
  WebSocketProvider? _webSocketProvider;
  bool _initialized = false;
  
  // Getters
  List<Notebook> get notebooks => _notebooksMap.values.toList();
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
    // Register handlers for all standardized resource.action events
    _webSocketProvider?.addEventListener('event', 'notebook.updated', _handleNotebookUpdate);
    _webSocketProvider?.addEventListener('event', 'notebook.created', _handleNotebookCreate);
    _webSocketProvider?.addEventListener('event', 'notebook.deleted', _handleNotebookDelete);
    _webSocketProvider?.addEventListener('event', 'note.created', _handleNoteCreate);
    _webSocketProvider?.addEventListener('event', 'note.deleted', _handleNoteDelete);
    
    print('NotebooksProvider: Event handlers registered for resource.action events');
  }
  
  void _unregisterEventHandlers() {
    _webSocketProvider?.removeEventListener('event', 'notebook.updated');
    _webSocketProvider?.removeEventListener('event', 'notebook.created');
    _webSocketProvider?.removeEventListener('event', 'notebook.deleted');
    _webSocketProvider?.removeEventListener('event', 'note.created');
    _webSocketProvider?.removeEventListener('event', 'note.deleted');
  }
  
  void _handleNotebookUpdate(Map<String, dynamic> message) {
    try {
      // Use the new parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? notebookId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
      
      if (notebookId != null) {
        print('NotebooksProvider: Received notebook.updated event for notebook ID $notebookId');
        
        // Fetch updated notebook data from server
        Future.delayed(Duration(milliseconds: 300), () {
          _fetchSingleNotebook(notebookId);
        });
      }
    } catch (e) {
      print('NotebooksProvider: Error handling notebook update: $e');
    }
  }

  // Handle notebook create events - simplified to match pattern
  void _handleNotebookCreate(Map<String, dynamic> message) {
    try {
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? notebookId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
      
      if (notebookId != null) {
        print('NotebooksProvider: Received notebook.created event for notebook ID $notebookId');
        
        // Check if this notebook already exists in our list
        if (_notebooksMap.containsKey(notebookId)) {
          print('NotebooksProvider: Notebook $notebookId already in list, skipping');
          return;
        }
        
        // Add a delay to ensure database transaction is complete
        Future.delayed(Duration(milliseconds: 500), () {
          // Get the notebook by ID directly
          ApiService.getNotebook(notebookId).then((newNotebook) {
            // Track ID to prevent duplicates
            _notebooksMap[notebookId] = newNotebook;
            print('NotebooksProvider: Added new notebook $notebookId to list');
            
            // Subscribe to this notebook
            if (_webSocketProvider != null) {
              _webSocketProvider!.subscribe('notebook', id: newNotebook.id);
              _webSocketProvider!.subscribe('notebook:notes', id: newNotebook.id);
            }
            
            notifyListeners();
          }).catchError((error) {
            print('NotebooksProvider: Error fetching new notebook $notebookId: $error');
          });
        });
      }
    } catch (e) {
      print('NotebooksProvider: Error handling notebook create: $e');
    }
  }

  void _handleNotebookDelete(Map<String, dynamic> message) {
    try {
      // Use the new parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? notebookId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
      
      if (notebookId != null) {
        print('NotebooksProvider: Received notebook.deleted event for notebook ID $notebookId');
        // Remove notebook from local state if it exists
        _notebooksMap.remove(notebookId);
        notifyListeners();
      }
    } catch (e) {
      print('NotebooksProvider: Error handling notebook delete: $e');
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
      if (_notebooksMap.containsKey(notebookId)) {
        _notebooksMap[notebookId] = notebook;
        print('NotebooksProvider: Updated existing notebook: $notebookId with ${notebook.notes.length} notes');
      } else {
        _notebooksMap[notebook.id] = notebook;
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
    if (!_notebooksMap.containsKey(notebookId)) {
      print('NotebooksProvider: Notebook not found in local state, skipping refresh');
      return;
    }
    
    // Add a delay to allow database to complete the transaction
    Future.delayed(Duration(milliseconds: 2000), () {
      print('NotebooksProvider: Attempting to fetch notebook $notebookId after delay');
      _fetchSingleNotebook(notebookId);
    });
  }
  
  void _handleNoteDelete(Map<String, dynamic> message) {
    try {
      // Use the parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      final String? notebookId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
      
      if (notebookId != null && noteId != null) {
        // If this notebook is in our list, update it
        if (_notebooksMap.containsKey(notebookId)) {
          // Remove the note from local state
          final currentNotebook = _notebooksMap[notebookId]!;
          final updatedNotes = currentNotebook.notes.where((note) => note.id != noteId).toList();
          
          _notebooksMap[notebookId] = Notebook(
            id: currentNotebook.id,
            name: currentNotebook.name,
            description: currentNotebook.description,
            userId: currentNotebook.userId,
            notes: updatedNotes,
          );
          
          notifyListeners();
        }
      }
    } catch (e) {
      print('NotebooksProvider: Error handling note delete: $e');
    }
  }

  // Fetch notebooks with pagination and duplicate prevention
  Future<void> fetchNotebooks({
    int page = 1, 
    int pageSize = 20,
    List<String>? excludeIds,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Fetch notebooks with pagination
      final fetchedNotebooks = await ApiService.fetchNotebooks(page: page, pageSize: pageSize);
      
      // Keep track of existing IDs if not starting fresh
      final existingIds = page > 1 ? _notebooksMap.keys.toSet() : <String>{};
      
      // On first page, clear the map unless specified to keep existing data
      if (page == 1) {
        _notebooksMap.clear();
      }
      
      // Only add notebooks that aren't already in our list
      for (var notebook in fetchedNotebooks) {
        // Skip if this ID should be excluded or already exists
        if ((excludeIds != null && excludeIds.contains(notebook.id)) || 
            existingIds.contains(notebook.id)) {
          continue;
        }
        
        _notebooksMap[notebook.id] = notebook;
      }
      
      // Subscribe to relevant events
      if (_webSocketProvider != null) {
        for (var notebook in _notebooksMap.values) {
          _webSocketProvider!.subscribe('notebook', id: notebook.id);
        }
      }
      
      print('NotebooksProvider: Fetched notebooks (page $page), total: ${_notebooksMap.length}');
    } catch (error) {
      print('Error fetching notebooks: $error');
      // Only clear on first page error
      if (page == 1) _notebooksMap.clear();
    }

    _isLoading = false;
    notifyListeners();
  }

  // Add single notebook from websocket event - more efficient version
  Future<void> addNotebookFromEvent(String notebookId) async {
    try {
      // Only fetch if we don't already have this notebook
      if (!_notebooksMap.containsKey(notebookId)) {
        final notebook = await ApiService.getNotebook(notebookId);
        _notebooksMap[notebookId] = notebook;
        
        // Subscribe to this notebook and its notes
        if (_webSocketProvider != null) {
          _webSocketProvider!.subscribe('notebook', id: notebook.id);
          _webSocketProvider!.subscribe('notebook:notes', id: notebook.id);
        }
        
        notifyListeners();
        print('NotebooksProvider: Added notebook $notebookId from WebSocket event');
      } else {
        print('NotebooksProvider: Notebook $notebookId already exists, skipping fetch');
      }
    } catch (error) {
      print('Error fetching notebook from event: $error');
    }
  }

  // Create a new notebook with optimized local update
  Future<Notebook?> createNotebook(String name, String description) async {
    try {
      final notebook = await ApiService.createNotebook(name, description);
      
      // Add to local state immediately instead of refetching all notebooks
      _notebooksMap[notebook.id] = notebook;
      
      // Subscribe to this notebook
      if (_webSocketProvider != null) {
        _webSocketProvider!.subscribe('notebook', id: notebook.id);
        _webSocketProvider!.subscribe('notebook:notes', id: notebook.id);
      }
      
      notifyListeners();
      return notebook;
    } catch (error) {
      print('Error creating notebook: $error');
      rethrow;
    }
  }

  Future<void> addNoteToNotebook(String notebookId, String title) async {
    try {
      final note = await ApiService.createNote(notebookId, title);
      if (_notebooksMap.containsKey(notebookId)) {
        final updatedNotebook = _notebooksMap[notebookId]!;
        final notes = List<Note>.from(updatedNotebook.notes)..add(note);
        _notebooksMap[notebookId] = Notebook(
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
      if (_notebooksMap.containsKey(notebookId)) {
        final updatedNotebook = _notebooksMap[notebookId]!;
        final notes = updatedNotebook.notes.where((note) => note.id != noteId).toList();
        _notebooksMap[notebookId] = Notebook(
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
      if (_notebooksMap.containsKey(id)) {
        _notebooksMap[id] = notebook;
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
      _notebooksMap.remove(id);
      
      // Unsubscribe from this notebook
      _webSocketService.unsubscribe('notebook', id: id);
      
      notifyListeners();
    } catch (error) {
      print('Error deleting notebook: $error');
      rethrow;
    }
  }

  // Add method to handle notebook deletion events
  void handleNotebookDeleted(String notebookId) {
    if (_notebooksMap.containsKey(notebookId)) {
      _notebooksMap.remove(notebookId);
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    _unregisterEventHandlers();
    super.dispose();
  }
}
