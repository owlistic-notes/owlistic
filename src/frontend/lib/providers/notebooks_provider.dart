import 'dart:async';
import 'package:flutter/material.dart';
import '../models/subscription.dart';
import '../models/notebook.dart';
import '../models/note.dart';
import '../services/notebook_service.dart';
import '../services/note_service.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import '../utils/logger.dart';
import '../utils/websocket_message_parser.dart';
import '../services/app_state_service.dart';
import '../viewmodel/notebooks_viewmodel.dart';

class NotebooksProvider with ChangeNotifier implements NotebooksViewModel {
  final Logger _logger = Logger('NotebooksProvider');
  
  // Using a map for O(1) lookups by ID
  final Map<String, Notebook> _notebooksMap = {};
  bool _isLoading = false;
  bool _isActive = false; // For lifecycle management
  bool _isInitialized = false;
  String? _errorMessage;
  
  // Services
  final NotebookService _notebookService;
  final NoteService _noteService;
  final AuthService _authService;
  final WebSocketService _webSocketService;
  
  // Add subscription for app state changes
  StreamSubscription? _resetSubscription;
  StreamSubscription? _connectionSubscription;
  final AppStateService _appStateService = AppStateService();
  
  // Constructor with dependency injection - add WebSocketService parameter
  NotebooksProvider({
    required NotebookService notebookService, 
    required NoteService noteService,
    required AuthService authService,
    required WebSocketService webSocketService
  }) : 
    _notebookService = notebookService,
    _noteService = noteService,
    _authService = authService,
    _webSocketService = webSocketService {
    // Listen for app reset events
    _resetSubscription = _appStateService.onResetState.listen((_) {
      resetState();
    });
    
    // Initialize event listeners
    _initializeEventListeners();
    
    // Listen for connection state changes
    _connectionSubscription = _webSocketService.connectionStateStream.listen((connected) {
      if (connected && _isActive) {
        // Resubscribe to events when connection is established
        _subscribeToEvents();
        // Resubscribe to existing notebooks
        _subscribeToExistingNotebooks();
      }
    });
    
    _isInitialized = true;
  }
  
  // Initialize WebSocket event listeners
  void _initializeEventListeners() {
    _logger.info('Setting up notebooks event listeners');
    _webSocketService.addEventListener('event', 'notebook.created', _handleNotebookCreated);
    _webSocketService.addEventListener('event', 'notebook.updated', _handleNotebookUpdated);
    _webSocketService.addEventListener('event', 'notebook.deleted', _handleNotebookDeleted);
    _webSocketService.addEventListener('event', 'note.created', _handleNoteCreate);
    _webSocketService.addEventListener('event', 'note.updated', _handleNoteUpdate);
    _webSocketService.addEventListener('event', 'note.deleted', _handleNoteDelete);
  }
  
  // Subscribe to events
  void _subscribeToEvents() {
    _webSocketService.subscribeToEvent('notebook.updated');
    _webSocketService.subscribeToEvent('notebook.created');
    _webSocketService.subscribeToEvent('notebook.deleted');
    _webSocketService.subscribeToEvent('note.created');
    _webSocketService.subscribeToEvent('note.updated');
    _webSocketService.subscribeToEvent('note.deleted');
  }
  
  // Subscribe to existing notebooks
  void _subscribeToExistingNotebooks() {
    if (_notebooksMap.isEmpty) return;
    
    _logger.info('Subscribing to ${_notebooksMap.length} existing notebooks');
    
    // Subscribe to global notebooks resource
    _webSocketService.subscribe('notebook');
    
    // Batch subscribe to individual notebooks
    final List<Subscription> pendingSubscriptions = [];
    
    for (var notebook in _notebooksMap.values) {
      if (notebook.id.isNotEmpty && !_webSocketService.isSubscribed('notebook', id: notebook.id)) {
        pendingSubscriptions.add(Subscription(resource: 'notebook', id: notebook.id));
      }
    }
    
    // Only batch subscribe if we have subscriptions to add
    if (pendingSubscriptions.isNotEmpty) {
      _webSocketService.batchSubscribe(pendingSubscriptions);
    }
  }
  
  // BaseViewModel implementation
  @override
  bool get isLoading => _isLoading;
  
  @override
  bool get isInitialized => _isInitialized;
  
  @override
  bool get isActive => _isActive;
  
  @override
  String? get errorMessage => _errorMessage;
  
  @override
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
  
  // NotebooksPresenter implementation
  @override
  List<Notebook> get notebooks => _notebooksMap.values.toList();
  
  // Clear state on logout
  @override
  void resetState() {
    _logger.info('Resetting NotebooksProvider state');
    _notebooksMap.clear();
    _errorMessage = null;
    _isActive = false;
    notifyListeners();
  }
  
  // Fetch notebooks with proper user filtering - updated to fetch notes for each notebook
  @override
  Future<void> fetchNotebooks({
    String? name, 
    int page = 1, 
    int pageSize = 20,
    List<String>? excludeIds,
  }) async {
    // Only process if provider is active
    if (!_isActive) {
      _logger.debug('Provider not active, ignoring create event');
      return;
    }
      
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
      
      // Make the REST API call to fetch notebooks
      final fetchedNotebooks = await _notebookService.fetchNotebooks(
        name: name,
        page: page,
        pageSize: pageSize,
      );
      
      _logger.debug('Fetched ${fetchedNotebooks.length} notebooks from API');
      
      // Clear existing notebooks if this is the first page
      if (page == 1) {
        _notebooksMap.clear();
      }
      
      // Fetch notes for each notebook
      for (var notebook in fetchedNotebooks) {
        // Skip notebooks that should be excluded
        if (excludeIds != null && excludeIds.contains(notebook.id)) {
          continue;
        }
        
        try {
          // Fetch notes for this notebook
          final notes = await _noteService.fetchNotesForNotebook(notebook.id);
          _logger.debug('Fetched ${notes.length} notes for notebook ${notebook.id}');
          
          // Create notebook with notes
          final notebookWithNotes = notebook.copyWith(notes: notes);
          _notebooksMap[notebook.id] = notebookWithNotes;
          
          // Subscribe to this notebook
          if (_webSocketService.isConnected) {
            if (notebook.id.isNotEmpty && 
                !_webSocketService.isSubscribed('notebook', id: notebook.id)) {
              _webSocketService.subscribe('notebook', id: notebook.id);
            }
          }
        } catch (e) {
          _logger.error('Error fetching notes for notebook ${notebook.id}', e);
          // Still add the notebook without notes rather than skipping it completely
          _notebooksMap[notebook.id] = notebook;
        }
      }
      
      // Subscribe to notebooks as a collection - only if not already subscribed
      if (_webSocketService.isConnected && 
          !_webSocketService.isSubscribed('notebook')) {
        _logger.debug('Subscribing to global notebooks resource');
        _webSocketService.subscribe('notebook');
      }
      
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
      
      _logger.info('Fetched ${fetchedNotebooks.length} notebooks with their notes');
    } catch (e) {
      _logger.error('Error fetching notebooks', e);
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Create a new notebook
  @override
  Future<Notebook?> createNotebook(String name, String description) async {
    try {
      // Get user ID from the auth service directly
      final currentUser = await _authService.getUserProfile();
      if (currentUser == null) {
        throw Exception('Cannot create notebook: No authenticated user');
      }
      
      // Create the notebook
      final notebook = await _notebookService.createNotebook(
        name, 
        description, 
      );
      
      // Subscribe to the new notebook
      _webSocketService.subscribe('notebook', id: notebook.id);
      
      return notebook;
    } catch (e) {
      _logger.error('Error creating notebook', e);
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }
  
  // Add a note to a notebook
  @override
  Future<Note?> addNoteToNotebook(String notebookId, String title) async {
    try {
      // Create the note via API
      final note = await _noteService.createNote(notebookId, title);
      
      // Subscribe to the new note
      _webSocketService.subscribe('note', id: note.id);
      
      // Update local notebook state by adding the note to it
      if (_notebooksMap.containsKey(notebookId)) {
        final notebook = _notebooksMap[notebookId];
        if (notebook != null) {
          final updatedNotes = List<Note>.from(notebook.notes)..add(note);
          final updatedNotebook = notebook.copyWith(notes: updatedNotes);
          _notebooksMap[notebookId] = updatedNotebook;
          _logger.info('Added note to notebook in local state');
          notifyListeners();
        }
      } else {
        // If notebook not in memory, fetch it to get updated
        _logger.info('Notebook not in memory, fetching it');
        await fetchNotebookById(notebookId);
      }
      
      return note;
    } catch (e) {
      _logger.error('Error adding note to notebook', e);
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }
  
  // Fetch a notebook by ID with its notes
  @override
  Future<Notebook?> fetchNotebookById(String id, {
    List<String>? excludeIds,
    bool addToExistingList = false,
    bool updateExisting = false
  }) async {
    // Skip if this ID should be excluded
    if (excludeIds != null && excludeIds.contains(id)) {
      _logger.info('Skipping excluded notebook ID: $id');
      return null;
    }
    
    try {
      _logger.info('Fetching notebook with ID: $id');
      
      // First fetch the notebook itself
      final notebook = await _notebookService.getNotebook(id);
      
      // Then fetch its notes
      final notes = await _noteService.fetchNotesForNotebook(id);
      _logger.info('Fetched ${notes.length} notes for notebook $id');
      
      // Create a new notebook with the notes
      final notebookWithNotes = notebook.copyWith(notes: notes);
      
      // Add to our map
      _notebooksMap[id] = notebookWithNotes;
      
      // Subscribe to this notebook
      _webSocketService.subscribe('notebook', id: id);
      
      // Always notify listeners to update UI
      notifyListeners();
      
      _logger.info('Successfully fetched and updated notebook: ${notebook.name}');
      return notebookWithNotes;
    } catch (e) {
      _logger.error('Error fetching notebook $id', e);
      return null;
    }
  }
  
  // Update a notebook
  @override
  Future<Notebook?> updateNotebook(String id, String name, String description) async {
    try {
      final notebook = await _notebookService.updateNotebook(id, name, description);
      
      // Update in our map
      _notebooksMap[id] = notebook;
      
      notifyListeners();
      return notebook;
    } catch (e) {
      _logger.error('Error updating notebook', e);
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }
  
  // Delete a notebook
  @override
  Future<void> deleteNotebook(String id) async {
    try {
      await _notebookService.deleteNotebook(id);
      
      // Unsubscribe from this notebook
      _webSocketService.unsubscribe('notebook', id: id);
      
      // Remove from our map
      _notebooksMap.remove(id);
      
      notifyListeners();
    } catch (e) {
      _logger.error('Error deleting notebook', e);
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }
  
  // Delete a note from a notebook
  @override
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
      _webSocketService.unsubscribe('note', id: noteId);
      
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
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }
  
  // Get a notebook by ID from cache or fetch if not available
  @override
  Notebook? getNotebook(String id) {
    return _notebooksMap[id];
  }
  
  // Activate/deactivate pattern for lifecycle management
  @override
  void activate() {
    _isActive = true;
    _logger.info('NotebooksProvider activated');
    
    // Subscribe to events when activated
    if (_webSocketService.isConnected) {
      _subscribeToEvents();
      _subscribeToExistingNotebooks();
    }
    
    fetchNotebooks(); // Load notebooks on activation
    notifyListeners(); // Notify about activation state change
  }
  
  @override
  void deactivate() {
    _isActive = false;
    _logger.info('NotebooksProvider deactivated');
    notifyListeners(); // Notify about deactivation state change
  }
  
  // WebSocket event handlers
  void _handleNotebookUpdated(Map<String, dynamic> message) {
    _logger.info('Notebook update event received');
    
    // Only process if provider is active
    if (!_isActive) {
      _logger.debug('Provider not active, ignoring create event');
      return;
    }

    try {
      // Use the standardized parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? notebookId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
      
      if (notebookId != null && notebookId.isNotEmpty) {
        _logger.info('Fetching updated notebook: $notebookId');
        fetchNotebookById(notebookId);
      } else {
        _logger.warning('Could not extract notebook_id from message');
      }
    } catch (e) {
      _logger.error('Error handling notebook update event', e);
    }
  }
  
  void _handleNotebookCreated(Map<String, dynamic> message) {
    _logger.info('Notebook created event received');
    
    // Only process if provider is active
    if (!_isActive) {
      _logger.debug('Provider not active, ignoring create event');
      return;
    }

    try {
      // Use the standardized parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? notebookId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
      
      if (notebookId != null && notebookId.isNotEmpty) {
        _logger.info('Fetching new notebook: $notebookId');
        fetchNotebookById(notebookId);
      } else {
        _logger.warning('Could not extract notebook_id from message');
      }
    } catch (e) {
      _logger.error('Error handling notebook create event', e);
    }
  }
  
  void _handleNotebookDeleted(Map<String, dynamic> message) {
    _logger.info('Notebook deleted event received');
    
    // Only process if provider is active
    if (!_isActive) {
      _logger.debug('Provider not active, ignoring create event');
      return;
    }

    try {
      // Use the standardized parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? notebookId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
      
      if (notebookId != null && notebookId.isNotEmpty && _notebooksMap.containsKey(notebookId)) {
        _logger.info('Removing deleted notebook: $notebookId');
        _notebooksMap.remove(notebookId);
        _webSocketService.unsubscribe('notebook', id: notebookId);
        notifyListeners();
      } else {
        _logger.warning('Could not extract notebook_id from message or notebook not found');
      }
    } catch (e) {
      _logger.error('Error handling notebook delete event', e);
    }
  }
  
  // Handler for note.created events
  void _handleNoteCreate(Map<String, dynamic> message) {
    // Only process if provider is active
    if (!_isActive) {
      _logger.debug('Provider not active, ignoring create event');
      return;
    }

    _logger.info('Note created event received');
    
    try {
      // Use the standardized parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? notebookId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
      
      if (notebookId != null && notebookId.isNotEmpty) {
        _logger.info('Refreshing notebook after note creation: $notebookId');
        fetchNotebookById(notebookId);
      } else {
        _logger.warning('Could not extract notebook_id from message');
      }
    } catch (e) {
      _logger.error('Error handling note create event', e);
    }
  }

  // Handler for note.updated events
  void _handleNoteUpdate(Map<String, dynamic> message) {
    if (!_isActive) {
      _logger.debug('Provider not active, ignoring update event');
      return;
    }
    
    _logger.info('Note updated event received');
    
    try {
      // Use the standardized parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? notebookId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
      
      if (notebookId != null && notebookId.isNotEmpty) {
        _logger.info('Refreshing notebook after note update: $notebookId');
        fetchNotebookById(notebookId);
      } else {
        _logger.warning('Could not extract notebook_id from message');
      }
    } catch (e) {
      _logger.error('Error handling note update event', e);
    }
  }
  
  // Handler for note.deleted events
  void _handleNoteDelete(Map<String, dynamic> message) {
    if (!_isActive) {
      _logger.debug('Provider not active, ignoring delete event');
      return;
    }
    
    _logger.info('Note deleted event received');
    
    try {
      // Use the standardized parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? notebookId = WebSocketModelExtractor.extractNotebookId(parsedMessage);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      // If we have both IDs, we can update the notebook locally without a fetch
      if (notebookId != null && noteId != null && 
          notebookId.isNotEmpty && noteId.isNotEmpty && 
          _notebooksMap.containsKey(notebookId)) {
        
        _logger.info('Updating notebook in memory after note deletion');
        final notebook = _notebooksMap[notebookId];
        if (notebook != null) {
          final updatedNotes = notebook.notes.where((note) => note.id != noteId).toList();
          final updatedNotebook = notebook.copyWith(notes: updatedNotes);
          _notebooksMap[notebookId] = updatedNotebook;
          notifyListeners();
        }
      } 
      // Otherwise fetch the notebook if we at least have its ID
      else if (notebookId != null && notebookId.isNotEmpty) {
        _logger.info('Refreshing notebook after note deletion: $notebookId');
        fetchNotebookById(notebookId);
      } else {
        _logger.warning('Could not extract notebook_id from message');
      }
    } catch (e) {
      _logger.error('Error handling note delete event', e);
    }
  }
  
  // Cleanup
  void cleanup() {
    _webSocketService.removeEventListener('event', 'notebook.updated');
    _webSocketService.removeEventListener('event', 'notebook.created');
    _webSocketService.removeEventListener('event', 'notebook.deleted');
    _webSocketService.removeEventListener('event', 'note.created');
    _webSocketService.removeEventListener('event', 'note.updated');
    _webSocketService.removeEventListener('event', 'note.deleted');
  }
  
  @override
  void dispose() {
    _resetSubscription?.cancel();
    _connectionSubscription?.cancel();
    cleanup();
    super.dispose();
  }
  
  // Update the notebooks list directly (useful for deletions)
  @override
  void updateNotebooksList(List<Notebook> updatedNotebooks) {
    _notebooksMap.clear();
    for (var notebook in updatedNotebooks) {
      _notebooksMap[notebook.id] = notebook;
    }
    notifyListeners();
    _logger.info('Updated notebooks list with ${updatedNotebooks.length} notebooks');
  }

  // Update just the notes collection of a specific notebook
  @override
  void updateNotebookNotes(String notebookId, List<Note> updatedNotes) {
    _logger.info('Updating notes for notebook: $notebookId');
  
    if (_notebooksMap.containsKey(notebookId)) {
      final notebook = _notebooksMap[notebookId];
      if (notebook != null) {
        final updatedNotebook = notebook.copyWith(notes: updatedNotes);
        _notebooksMap[notebookId] = updatedNotebook;
        
        // Always notify listeners to update UI
        notifyListeners();
        
        _logger.info('Successfully updated notes for notebook $notebookId: ${updatedNotes.length} notes');
      }
    } else {
      _logger.info('Notebook $notebookId not found, cannot update notes');
    }
  }

  // Remove a notebook by ID
  @override
  void removeNotebookById(String notebookId) {
    _logger.info('Removing notebook with ID: $notebookId');
  
    if (_notebooksMap.containsKey(notebookId)) {
      _notebooksMap.remove(notebookId);
      
      // Always notify listeners to update UI
      notifyListeners();
      
      _logger.info('Successfully removed notebook $notebookId from map');
    } else {
      _logger.info('Notebook $notebookId not found, nothing to remove');
    }
  }
}
