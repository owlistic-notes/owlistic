import 'dart:async';
import 'package:flutter/material.dart';
import 'package:thinkstack/models/subscription.dart';
import '../models/notebook.dart';
import '../models/note.dart';
import '../services/notebook_service.dart';
import '../services/note_service.dart';
import '../services/auth_service.dart';
import '../services/base_service.dart';
import 'websocket_provider.dart';
import '../utils/logger.dart';

class NotebooksProvider with ChangeNotifier {
  final Logger _logger = Logger('NotebooksProvider');
  
  // Using a map for O(1) lookups by ID
  final Map<String, Notebook> _notebooksMap = {};
  bool _isLoading = false;
  bool _isActive = false; // For lifecycle management
  String? _error;
  
  // Services
  final NotebookService _notebookService;
  final NoteService _noteService;
  final AuthService _authService;
  WebSocketProvider? _webSocketProvider;
  
  // Constructor with dependency injection
  NotebooksProvider({
    NotebookService? notebookService, 
    NoteService? noteService,
    AuthService? authService
  }) : 
    _notebookService = notebookService ?? ServiceLocator.get<NotebookService>(),
    _noteService = noteService ?? ServiceLocator.get<NoteService>(),
    _authService = authService ?? ServiceLocator.get<AuthService>();
  
  // Getters
  List<Notebook> get notebooks => _notebooksMap.values.toList();
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  // Clear state on logout
  void resetState() {
    _logger.info('Resetting NotebooksProvider state');
    _notebooksMap.clear();
    _error = null;
    _isActive = false;
    notifyListeners();
  }
  
  // Fetch notebooks with proper user filtering
  Future<void> fetchNotebooks({
    String? name, 
    int page = 1, 
    int pageSize = 20,
    List<String>? excludeIds,
  }) async {
    // Remove the _isActive check to allow fetching notebooks even if not explicitly activated
    // This allows fetching from other screens like the home screen after login
    
    // Get current user ID for filtering
    final currentUser = await _authService.getUserProfile();
    if (currentUser == null) {
      _logger.warning('Cannot fetch notebooks: No authenticated user');
      return;
    }
    
    _isLoading = true;
    notifyListeners();
    
    try {
      _logger.info('Fetching notebooks for user: ${currentUser.id}');
      final fetchedNotebooks = await _notebookService.fetchNotebooks(
        name: name,
        page: page,
        pageSize: pageSize,
        userId: currentUser.id,  // Only fetch notebooks where user is owner
      );
      
      // Clear existing notebooks if this is the first page
      if (page == 1) {
        _notebooksMap.clear();
      }
      
      // Add to map (prevents duplicates)
      for (var notebook in fetchedNotebooks) {
        // Skip notebooks that should be excluded
        if (excludeIds != null && excludeIds.contains(notebook.id)) {
          continue;
        }
        
        _notebooksMap[notebook.id] = notebook;
        
        // Subscribe to this notebook with explicit ID validation and duplicate prevention
        if (_webSocketProvider != null && _webSocketProvider!.isConnected) {
          if (notebook.id.isNotEmpty && 
              !_webSocketProvider!.isSubscribed('notebook', id: notebook.id)) {
            _logger.debug('Subscribing to notebook with ID: ${notebook.id}');
            _webSocketProvider?.subscribe('notebook', id: notebook.id);
          }
        }
      }
      
      // Subscribe to notebooks as a collection - only if not already subscribed
      if (_webSocketProvider != null && _webSocketProvider!.isConnected && 
          !_webSocketProvider!.isSubscribed('notebook')) {
        _logger.debug('Subscribing to global notebooks resource');
        _webSocketProvider?.subscribe('notebook');
      }
      
      _isLoading = false;
      _error = null;
      notifyListeners();
      
      _logger.info('Fetched ${fetchedNotebooks.length} notebooks');
    } catch (e) {
      _logger.error('Error fetching notebooks', e);
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Create a new notebook
  Future<Notebook?> createNotebook(String name, String description) async {
    try {
      // Get user ID from the auth service directly
      final currentUser = await _authService.getUserProfile();
      if (currentUser == null) {
        throw Exception('Cannot create notebook: No authenticated user');
      }
      
      final userId = currentUser.id;
      
      // Create the notebook
      final notebook = await _notebookService.createNotebook(
        name, 
        description, 
        userId
      );
      
      // Subscribe to the new notebook
      _webSocketProvider?.subscribe('notebook', id: notebook.id);
      
      return notebook;
    } catch (e) {
      _logger.error('Error creating notebook', e);
      _error = e.toString();
      notifyListeners();
      throw e;
    }
  }
  
  // Add a note to a notebook
  Future<Note?> addNoteToNotebook(String notebookId, String title) async {
    try {
      // Get user ID from the auth service directly
      final currentUser = await _authService.getUserProfile();
      final userId = currentUser?.id ?? '';
      
      // Create the note
      final note = await _noteService.createNote(notebookId, title, userId);
      
      // Subscribe to the new note
      _webSocketProvider?.subscribe('note', id: note.id);
      
      return note;
    } catch (e) {
      _logger.error('Error adding note to notebook', e);
      _error = e.toString();
      notifyListeners();
      throw e;
    }
  }
  
  // Fetch a notebook by ID
  Future<Notebook?> fetchNotebookById(String id, {List<String>? excludeIds}) async {
    // Skip if this ID should be excluded
    if (excludeIds != null && excludeIds.contains(id)) {
      _logger.info('Skipping excluded notebook ID: $id');
      return null;
    }
    
    try {
      final notebook = await _notebookService.getNotebook(id);
      
      // Add to our map
      _notebooksMap[id] = notebook;
      
      // Subscribe to this notebook
      _webSocketProvider?.subscribe('notebook', id: id);
      
      notifyListeners();
      return notebook;
    } catch (e) {
      _logger.error('Error fetching notebook $id', e);
      return null;
    }
  }
  
  // Update a notebook
  Future<Notebook?> updateNotebook(String id, String name, String description) async {
    try {
      final notebook = await _notebookService.updateNotebook(id, name, description);
      
      // Update in our map
      _notebooksMap[id] = notebook;
      
      notifyListeners();
      return notebook;
    } catch (e) {
      _logger.error('Error updating notebook', e);
      _error = e.toString();
      notifyListeners();
      throw e;
    }
  }
  
  // Delete a notebook
  Future<void> deleteNotebook(String id) async {
    try {
      await _notebookService.deleteNotebook(id);
      
      // Unsubscribe from this notebook
      _webSocketProvider?.unsubscribe('notebook', id: id);
      
      // Remove from our map
      _notebooksMap.remove(id);
      
      notifyListeners();
    } catch (e) {
      _logger.error('Error deleting notebook', e);
      _error = e.toString();
      notifyListeners();
      throw e;
    }
  }
  
  // Delete a note from a notebook
  Future<void> deleteNote(String notebookId, String noteId) async {
    try {
      // First find the notebook
      final notebook = _notebooksMap[notebookId];
      if (notebook == null) {
        _logger.error('Cannot delete note: notebook $notebookId not found');
        throw Exception('Notebook not found');
      }
      
      // Use the note service to delete the note
      await _noteService.deleteNote(noteId);
      
      // Unsubscribe from this note's events
      _webSocketProvider?.unsubscribe('note', id: noteId);
      
      // If we have the notebook in memory, update it by removing the note
      if (_notebooksMap.containsKey(notebookId)) {
        final updatedNotes = notebook.notes.where((note) => note.id != noteId).toList();
        final updatedNotebook = notebook.copyWith(notes: updatedNotes);
        _notebooksMap[notebookId] = updatedNotebook;
        
        _logger.info('Removed note $noteId from notebook $notebookId in local state');
        notifyListeners();
      }
    } catch (e) {
      _logger.error('Error deleting note $noteId from notebook $notebookId', e);
      _error = e.toString();
      notifyListeners();
      throw e;
    }
  }
  
  // Get a notebook by ID from cache or fetch if not available
  Notebook? getNotebook(String id) {
    return _notebooksMap[id];
  }
  
  // Activate/deactivate pattern for lifecycle management
  void activate() {
    _isActive = true;
    _logger.info('NotebooksProvider activated');
    fetchNotebooks(); // Load notebooks on activation
  }
  
  void deactivate() {
    _isActive = false;
    _logger.info('NotebooksProvider deactivated');
  }
  
  // Set WebSocket provider for real-time updates
  void setWebSocketProvider(WebSocketProvider provider) {
    if (_webSocketProvider == provider) return;
    
    // Unregister and unsubscribe from previous provider
    if (_webSocketProvider != null) {
      _webSocketProvider!.removeEventListener('event', 'notebook.updated');
      _webSocketProvider!.removeEventListener('event', 'notebook.created');
      _webSocketProvider!.removeEventListener('event', 'notebook.deleted');
      
      // Unsubscribe from events
      if (_webSocketProvider!.isConnected) {
        _webSocketProvider?.unsubscribeFromEvent('notebook.updated');
        _webSocketProvider?.unsubscribeFromEvent('notebook.created');
        _webSocketProvider?.unsubscribeFromEvent('notebook.deleted');
      }
    }
    
    _webSocketProvider = provider;
    
    // Register event listeners
    provider.addEventListener('event', 'notebook.updated', _handleNotebookUpdate);
    provider.addEventListener('event', 'notebook.created', _handleNotebookCreate);
    provider.addEventListener('event', 'notebook.deleted', _handleNotebookDelete);
    
    // Subscribe to events using correct pattern
    if (provider.isConnected) {
      provider.subscribeToEvent('notebook.updated');
      provider.subscribeToEvent('notebook.created');
      provider.subscribeToEvent('notebook.deleted');
    }
    
    _logger.info('WebSocketProvider set for NotebooksProvider');
    
    // If we already have notebooks, subscribe to them - only if not already subscribed
    if (_notebooksMap.isNotEmpty && provider.isConnected) {
      _logger.info('Subscribing to existing notebooks after WebSocketProvider connection');
      
      // First subscribe to the global notebooks resource - only if not already subscribed
      if (!provider.isSubscribed('notebook')) {
        provider.subscribe('notebook');
      }
      
      // Batch subscribe to individual notebooks to minimize subscription messages
      final List<Subscription> pendingSubscriptions = [];
      
      // Then subscribe to individual notebooks
      for (var notebook in _notebooksMap.values) {
        if (notebook.id.isNotEmpty && !provider.isSubscribed('notebook', id: notebook.id)) {
          pendingSubscriptions.add(Subscription(resource: 'notebook', id: notebook.id));
        }
      }
      
      // Only batch subscribe if we have subscriptions to add
      if (pendingSubscriptions.isNotEmpty) {
        provider.batchSubscribe(pendingSubscriptions);
      }
    } else if (provider.isConnected) {
      // Subscribe to global notebooks even if we don't have any yet - if not already subscribed
      if (!provider.isSubscribed('notebook')) {
        _logger.info('No notebooks in memory yet, subscribing to global notebooks resource');
        provider.subscribe('notebook');
      }
    }
  }
  
  // WebSocket event handlers
  void _handleNotebookUpdate(Map<String, dynamic> message) {
    _logger.info('Notebook update event received');
    
    // Only process if provider is active
    if (!_isActive) {
      _logger.debug('Provider not active, ignoring update');
      return;
    }
    
    try {
      final payload = message['payload'];
      if (payload != null && payload['data'] != null) {
        final data = payload['data'];
        String notebookId = '';
        
        // Extract notebook ID
        if (data['id'] != null) {
          notebookId = data['id'].toString();
        } else if (data['notebook_id'] != null) {
          notebookId = data['notebook_id'].toString();
        }
        
        if (notebookId.isNotEmpty) {
          _logger.info('Fetching updated notebook: $notebookId');
          fetchNotebookById(notebookId);
        }
      }
    } catch (e) {
      _logger.error('Error handling notebook update event', e);
    }
  }
  
  void _handleNotebookCreate(Map<String, dynamic> message) {
    _logger.info('Notebook created event received');
    
    // Only process if provider is active
    if (!_isActive) {
      _logger.debug('Provider not active, ignoring create event');
      return;
    }
    
    try {
      final payload = message['payload'];
      if (payload != null && payload['data'] != null) {
        final data = payload['data'];
        String notebookId = '';
        
        // Extract notebook ID
        if (data['id'] != null) {
          notebookId = data['id'].toString();
        } else if (data['notebook_id'] != null) {
          notebookId = data['notebook_id'].toString();
        }
        
        if (notebookId.isNotEmpty) {
          _logger.info('Fetching new notebook: $notebookId');
          fetchNotebookById(notebookId);
        }
      }
    } catch (e) {
      _logger.error('Error handling notebook create event', e);
    }
  }
  
  void _handleNotebookDelete(Map<String, dynamic> message) {
    _logger.info('Notebook deleted event received');
    
    // Only process if provider is active
    if (!_isActive) {
      _logger.debug('Provider not active, ignoring delete event');
      return;
    }
    
    try {
      final payload = message['payload'];
      if (payload != null && payload['data'] != null) {
        final data = payload['data'];
        String notebookId = '';
        
        // Extract notebook ID
        if (data['id'] != null) {
          notebookId = data['id'].toString();
        } else if (data['notebook_id'] != null) {
          notebookId = data['notebook_id'].toString();
        }
        
        if (notebookId.isNotEmpty && _notebooksMap.containsKey(notebookId)) {
          _logger.info('Removing deleted notebook: $notebookId');
          _notebooksMap.remove(notebookId);
          _webSocketProvider?.unsubscribe('notebook', id: notebookId);
          notifyListeners();
        }
      }
    } catch (e) {
      _logger.error('Error handling notebook delete event', e);
    }
  }
  
  // Cleanup
  void cleanup() {
    if (_webSocketProvider != null) {
      _webSocketProvider!.removeEventListener('event', 'notebook.updated');
      _webSocketProvider!.removeEventListener('event', 'notebook.created');
      _webSocketProvider!.removeEventListener('event', 'notebook.deleted');
      
      // Unsubscribe from events
      if (_webSocketProvider!.isConnected) {
        _webSocketProvider?.unsubscribeFromEvent('notebook.updated');
        _webSocketProvider?.unsubscribeFromEvent('notebook.created');
        _webSocketProvider?.unsubscribeFromEvent('notebook.deleted');
      }
    }
  }
  
  @override
  void dispose() {
    cleanup();
    super.dispose();
  }
}
