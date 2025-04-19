import 'dart:async';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../models/notebook.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'websocket_provider.dart';
import '../utils/websocket_message_parser.dart';
import '../utils/logger.dart';

class NotebooksProvider with ChangeNotifier {
  final Logger _logger = Logger('NotebooksProvider');
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
    _logger.info('NotebooksProvider initialized');
  }

  // Called by ProxyProvider in main.dart
  void initialize(WebSocketProvider webSocketProvider) {
    if (_initialized) return;
    _initialized = true;
    
    _webSocketProvider = webSocketProvider;
    _registerEventHandlers();
    
    _logger.info('NotebooksProvider registered event handlers');
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
    
    _logger.info('Event handlers registered for resource.action events');
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
        _logger.info('Received notebook.updated event for notebook ID $notebookId');
        
        // Fetch updated notebook data from server
        Future.delayed(Duration(milliseconds: 300), () {
          _fetchSingleNotebook(notebookId);
        });
      }
    } catch (e) {
      _logger.error('Error handling notebook update: $e');
    }
  }

  // Handle notebook create events - simplified to match pattern
  void _handleNotebookCreate(Map<String, dynamic> message) {
    try {
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? notebookId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
      
      if (notebookId != null) {
        _logger.info('Received notebook.created event for notebook ID $notebookId');
        
        // Check if this notebook already exists in our list
        if (_notebooksMap.containsKey(notebookId)) {
          _logger.info('Notebook $notebookId already in list, skipping');
          return;
        }
        
        // Add a delay to ensure database transaction is complete
        Future.delayed(Duration(milliseconds: 500), () {
          // Get the notebook by ID directly
          ApiService.getNotebook(notebookId).then((newNotebook) {
            // Track ID to prevent duplicates
            _notebooksMap[notebookId] = newNotebook;
            _logger.info('Added new notebook $notebookId to list');
            
            // Subscribe to this notebook
            if (_webSocketProvider != null) {
              _webSocketProvider!.subscribe('notebook', id: newNotebook.id);
              _webSocketProvider!.subscribe('notebook:notes', id: newNotebook.id);
            }
            
            notifyListeners();
          }).catchError((error) {
            _logger.error('Error fetching new notebook $notebookId: $error');
          });
        });
      }
    } catch (e) {
      _logger.error('Error handling notebook create: $e');
    }
  }

  void _handleNotebookDelete(Map<String, dynamic> message) {
    try {
      // Use the new parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? notebookId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
      
      if (notebookId != null) {
        _logger.info('Received notebook.deleted event for notebook ID $notebookId');
        // Remove notebook from local state if it exists
        _notebooksMap.remove(notebookId);
        notifyListeners();
      }
    } catch (e) {
      _logger.error('Error handling notebook delete: $e');
    }
  }

  // Fetch a single notebook
  Future<Notebook> _fetchSingleNotebook(String notebookId) async {
    _logger.info('Fetching single notebook: $notebookId');
    try {
      // Use ApiService to fetch the notebook by ID
      final notebook = await ApiService.getNotebook(notebookId);
      
      _logger.info('Fetched notebook ${notebook.id} with ${notebook.notes.length} notes');
      
      // Check if notebook exists in our list
      if (_notebooksMap.containsKey(notebookId)) {
        _notebooksMap[notebookId] = notebook;
        _logger.info('Updated existing notebook: $notebookId with ${notebook.notes.length} notes');
      } else {
        _notebooksMap[notebook.id] = notebook;
        _logger.info('Added new notebook: $notebookId with ${notebook.notes.length} notes');
        
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
      _logger.error('Error fetching notebook: $error');
      throw error;
    }
  }

  // Public method to fetch a single notebook by ID
  Future<Notebook?> fetchNotebookById(String notebookId) async {
    try {
      final notebook = await _fetchSingleNotebook(notebookId);
      return notebook;
    } catch (error) {
      _logger.error('Error in fetchNotebookById: $error');
      return null;
    }
  }
  
  void _handleNoteCreate(Map<String, dynamic> message) {
    _logger.info('Received note.created event');
    
    try {
      // Parse message using the new parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      
      // Extract note_id and notebook_id using the extractor
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      final String? notebookId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
      
      _logger.info('Extracted from event: noteId=$noteId, notebookId=$notebookId');
      
      // If we have a notebook ID, refresh it
      if (notebookId != null) {
        _logger.info('Will refresh notebook $notebookId from note.created event');
        _refreshNotebookWithNote(notebookId);
        return;
      }
      
      // If we only have a note ID, fetch the note to get its notebook
      if (noteId != null) {
        _logger.info('Attempting to fetch note $noteId to find its notebook');
        
        ApiService.getNote(noteId).then((note) {
          _logger.info('Found note belongs to notebook ${note.notebookId}');
          _refreshNotebookWithNote(note.notebookId);
        }).catchError((e) {
          _logger.error('Failed to fetch note details: $e');
        });
        return;
      }

      _logger.warning('Not enough information to process note creation');
    } catch (e) {
      _logger.error('Error handling note create: $e');
    }
  }
  
  // Helper method to refresh a notebook with new note data
  void _refreshNotebookWithNote(String notebookId) {
    _logger.info('Will refresh notebook $notebookId');
    
    // Check if this notebook is in our local state
    if (!_notebooksMap.containsKey(notebookId)) {
      _logger.info('Notebook not found in local state, skipping refresh');
      return;
    }
    
    // Add a delay to allow database to complete the transaction
    Future.delayed(Duration(milliseconds: 2000), () {
      _logger.info('Attempting to fetch notebook $notebookId after delay');
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
      _logger.error('Error handling note delete: $e');
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
      
      _logger.info('Fetched notebooks (page $page), total: ${_notebooksMap.length}');
    } catch (error) {
      _logger.error('Error fetching notebooks: $error');
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
        _logger.info('Added notebook $notebookId from WebSocket event');
      } else {
        _logger.info('Notebook $notebookId already exists, skipping fetch');
      }
    } catch (error) {
      _logger.error('Error fetching notebook from event: $error');
    }
  }

  // Create a new notebook - no optimistic updates
  Future<Notebook?> createNotebook(String name, String description) async {
    try {
      // Create the notebook on server
      final notebook = await ApiService.createNotebook(name, description);
      
      // Subscribe to this notebook
      if (_webSocketProvider != null) {
        _webSocketProvider!.subscribe('notebook', id: notebook.id);
        _webSocketProvider!.subscribe('notebook:notes', id: notebook.id);
      }
      
      _logger.info('Created notebook: $name, waiting for event');
      return notebook;
    } catch (error) {
      _logger.error('Error creating notebook: $error');
      rethrow;
    }
  }

  // Add note to notebook - no optimistic updates
  Future<Note?> addNoteToNotebook(String notebookId, String title) async {
    try {
      // Create note on server
      final note = await ApiService.createNote(notebookId, title);
      _logger.info('Added note to notebook: $notebookId, waiting for event');
      return note;
    } catch (error) {
      _logger.error('Error adding note to notebook: $error');
      rethrow;
    }
  }
  
  // Delete note from notebook - no optimistic updates
  Future<void> deleteNoteFromNotebook(String notebookId, String noteId) async {
    try {
      // Delete note on server
      await ApiService.deleteNoteFromNotebook(notebookId, noteId);
      _logger.info('Deleted note from notebook, waiting for event');
    } catch (error) {
      _logger.error('Error deleting note from notebook: $error');
      rethrow;
    }
  }

  // Update notebook - no optimistic updates
  Future<void> updateNotebook(String id, String name, String description) async {
    try {
      // Update notebook on server
      await ApiService.updateNotebook(id, name, description);
      _logger.info('Updated notebook: $name, waiting for event');
    } catch (error) {
      _logger.error('Error updating notebook: $error');
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
      _logger.error('Error deleting notebook: $error');
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
