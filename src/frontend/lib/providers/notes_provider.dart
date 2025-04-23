import 'dart:async';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/note_service.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import '../services/base_service.dart';
import '../utils/websocket_message_parser.dart';
import '../utils/logger.dart';
import '../services/block_service.dart';
import '../services/app_state_service.dart';

class NotesProvider with ChangeNotifier {
  final Logger _logger = Logger('NotesProvider');
  // Use a Map instead of a List to prevent duplicates
  final Map<String, Note> _notesMap = {};
  bool _isLoading = false;
  final Set<String> _activeNoteIds = {};
  
  // Services
  final NoteService _noteService;
  final AuthService _authService;
  final BlockService _blockService;
  final WebSocketService _webSocketService = WebSocketService();
  final AppStateService _appStateService = AppStateService();
  
  // Subscriptions
  StreamSubscription? _resetSubscription;
  StreamSubscription? _connectionSubscription;

  // Constructor with dependency injection
  NotesProvider({NoteService? noteService, AuthService? authService, required BlockService blockService}) 
    : _noteService = noteService ?? ServiceLocator.get<NoteService>(),
      _authService = authService ?? ServiceLocator.get<AuthService>(),
      _blockService = blockService {
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
      }
    });
  }

  // Getters
  List<Note> get notes => _notesMap.values.toList();
  
  // Fixed: Changed updatedAt to a different sorting method since Note doesn't have updatedAt
  List<Note> get recentNotes {
    final notesList = _notesMap.values.toList();
    // Sort by ID for now, or any other field available in your Note model
    notesList.sort((a, b) => b.id.compareTo(a.id));
    return notesList.take(5).toList();
  }
  
  bool get isLoading => _isLoading;
  
  Note? getNoteById(String id) {
    try {
      return _notesMap[id];
    } catch (e) {
      return null;
    }
  }

  // Reset state on logout
  void resetState() {
    _logger.info('Resetting NotesProvider state');
    _notesMap.clear();
    _activeNoteIds.clear();
    _isActive = false;
    notifyListeners();
  }

  // Initialize WebSocket event listeners
  void _initializeEventListeners() {
    _webSocketService.addEventListener('event', 'note.updated', _handleNoteUpdate);
    _webSocketService.addEventListener('event', 'note.created', _handleNoteCreate);
    _webSocketService.addEventListener('event', 'note.deleted', _handleNoteDelete);
  }
  
  // Subscribe to events
  void _subscribeToEvents() {
    _webSocketService.subscribeToEvent('note.updated');
    _webSocketService.subscribeToEvent('note.created');
    _webSocketService.subscribeToEvent('note.deleted');
  }

  // Mark a note as active/inactive
  void activateNote(String noteId) {
    _activeNoteIds.add(noteId);
    _webSocketService.subscribe('note', id: noteId);
    _logger.debug('Note $noteId activated');
  }
  
  void deactivateNote(String noteId) {
    _activeNoteIds.remove(noteId);
    _logger.debug('Note $noteId deactivated');
  }

  // Handle note update events
  void _handleNoteUpdate(Map<String, dynamic> message) {
    try {
      // Use the new parser to extract data
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      if (noteId != null) {
        _fetchSingleNote(noteId);
      } else {
        _logger.warning('Could not find note_id in update message');
      }
    } catch (e) {
      _logger.error('Error handling note update: $e');
    }
  }

  // Handle note create events with similar pattern to notebooks and blocks
  void _handleNoteCreate(Map<String, dynamic> message) {
    // Check if provider is active
    if (!_isActive) {
      _logger.info('Ignoring note.created event because provider is not active');
      return;
    }
    
    _logger.info('Received note.created event: ${message.toString()}');
    
    try {
      // Use the new parser to extract data
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      if (noteId != null) {
        _logger.info('Found note_id: $noteId');
        
        // Check if we already have this note
        if (_notesMap.containsKey(noteId)) {
          _logger.info('Note $noteId already exists in local state, skipping fetch');
          return;
        }
        
        // Add a short delay to avoid race condition with database
        Future.delayed(const Duration(milliseconds: 500), () {
          // Only proceed if provider is still active
          if (!_isActive) return;
          
          // Fetch the note by ID directly
          _noteService.getNote(noteId).then((newNote) {
            // Only add if provider is active and note is not deleted
            if (_isActive && newNote.deletedAt == null) {
              _notesMap[noteId] = newNote;
              _logger.info('Added new note $noteId to list');
              
              // Subscribe to this note
              _webSocketService.subscribe('note', id: newNote.id);
              
              notifyListeners();
            } else {
              _logger.info('Note $noteId was already added or is deleted or provider inactive');
            }
          }).catchError((error) {
            _logger.error('Error fetching new note $noteId: $error');
          });
        });
      } else {
        _logger.warning('Could not extract note_id from message');
      }
    } catch (e) {
      _logger.error('Error handling note create: $e');
    }
  }
  
  // Handle note delete events
  void _handleNoteDelete(Map<String, dynamic> message) {
    if (!_isActive) return;
    
    _logger.info('Received note.deleted event: ${message.toString()}');
    
    try {
      // Use the new parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      if (noteId != null) {
        _logger.info('Received note.deleted event for note ID $noteId');
        handleNoteDeleted(noteId);
      } else {
        _logger.warning('Could not extract note_id from message');
      }
    } catch (e) {
      _logger.error('Error handling note delete: $e', e);
    }
  }

  // Fetch a single note by ID
  Future<Note> _fetchSingleNote(String noteId) async {
    try {
      final note = await _noteService.getNote(noteId);
      
      // Check if this note already exists in our list
      if (_notesMap.containsKey(noteId)) {
        _notesMap[noteId] = note;
      } else {
        _notesMap[noteId] = note;
      }
      
      // Subscribe to this note
      _webSocketService.subscribe('note', id: noteId);
      
      notifyListeners();
      return note;
    } catch (error) {
      _logger.error('Error fetching note $noteId: $error');
      throw error;
    }
  }

  // Public method to fetch a single note by ID
  Future<Note?> fetchNoteById(String noteId) async {
    try {
      final note = await _fetchSingleNote(noteId);
      return note;
    } catch (error) {
      _logger.error('Error in fetchNoteById: $error');
      return null;
    }
  }

  // Fetch notes with pagination and proper user filtering
  Future<void> fetchNotes({int page = 1, List<String>? excludeIds}) async {
    // Check if user is logged in
    final currentUser = await _authService.getUserProfile();
    if (currentUser == null) {
      _logger.warning('Cannot fetch notes: No authenticated user');
      return;
    }

    _isLoading = true;
    notifyListeners();
    
    try {
      // Fetch notes from API with user filter (API must filter by owner role)
      final fetchedNotes = await _noteService.fetchNotes(
        page: page,
      );
      
      // Keep track of existing IDs if not starting fresh
      final existingIds = page > 1 ? _notesMap.keys.toSet() : <String>{};
      
      // Update the map without replacing existing notes if first page
      if (page == 1) {
        _notesMap.clear();
      }
      
      // Add new notes to the map, skipping duplicates
      for (var note in fetchedNotes) {
        // Skip if this ID should be excluded or already exists
        if ((excludeIds != null && excludeIds.contains(note.id)) || 
            existingIds.contains(note.id)) {
          continue;
        }
        
        _notesMap[note.id] = note;
        
        // Subscribe to this note for real-time updates - only if not already subscribed
        if (!_webSocketService.isSubscribed('note', id: note.id)) {
          _webSocketService.subscribe('note', id: note.id);
        }
      }
      
      _isLoading = false;
      notifyListeners();
    } catch (error) {
      _logger.error('Error fetching notes', error);
      _isLoading = false;
      notifyListeners();
    }
  }

  // Add single note from websocket event
  Future<void> addNoteFromEvent(String noteId) async {
    if (!_isActive) return;
    
    try {
      // Only fetch if we don't already have this note
      if (!_notesMap.containsKey(noteId)) {
        _logger.info('Fetching note $noteId from event');
        
        final note = await _noteService.getNote(noteId);
        
        // Only add if the note is not deleted
        if (note.deletedAt == null) {
          _notesMap[noteId] = note;
          
          // Subscribe to this note
          _webSocketService.subscribe('note', id: note.id);
          
          _logger.info('Added note $noteId from WebSocket event');
          notifyListeners();
        } else {
          _logger.info('Note $noteId is deleted, not adding to list');
        }
      } else {
        _logger.debug('Note $noteId already exists, skipping fetch');
      }
    } catch (error) {
      _logger.error('Error fetching note from event: $error');
    }
  }

  // Create a new note - get user ID from auth service
  Future<Note?> createNote(String notebookId, String title) async {
    try {
      // Create note on server via REST API
      final note = await _noteService.createNote(notebookId, title);
      
      // Add to local state
      _notesMap[note.id] = note;
      
      // Only subscribe to WebSocket events for this note
      _webSocketService.subscribe('note', id: note.id);
      
      // Notify listeners about the new note
      notifyListeners();
      
      _logger.info('Created note: $title with ID: ${note.id}');
      return note;
    } catch (error) {
      _logger.error('Error creating note: $error');
      rethrow;
    }
  }

  // Delete a note - ensure API call and notification
  Future<void> deleteNote(String id) async {
    try {
      _logger.info('Deleting note $id via API');
      
      // Delete note on server via REST API
      await _noteService.deleteNote(id);
      
      // Update local state
      _notesMap.remove(id);
      
      // Unsubscribe from WebSocket events for this note
      _webSocketService.unsubscribe('note', id: id);
      
      // Notify listeners about the deletion
      notifyListeners();
      
      _logger.info('Deleted note: $id');
    } catch (error) {
      _logger.error('Error deleting note: $error');
      rethrow;
    }
  }

  // Update a note using API call
  Future<Note?> updateNote(String id, String title) async {
    try {
      _logger.info('Updating note $id title to: $title via API');
      
      // Update note via REST API call
      final updatedNote = await _noteService.updateNote(id, title);
      
      // Update local state if we have this note
      if (_notesMap.containsKey(id)) {
        _notesMap[id] = updatedNote;
        _logger.info('Updated note $id title to: $title');
        
        // Always notify listeners to update UI
        notifyListeners();
      }
      
      return updatedNote;
    } catch (error) {
      _logger.error('Error updating note: $error');
      return null;
    }
  }

  // Activate/deactivate provider state management
  bool _isActive = false;

  void activate() {
    _isActive = true;
    _logger.info('NotesProvider activated');
    
    // Subscribe to events when activated
    if (_webSocketService.isConnected) {
      _subscribeToEvents();
    }
  }

  void deactivate() {
    _isActive = false;
    _logger.info('NotesProvider deactivated');
  }

  // Add this method to handle note deletion events with more robust implementation
  void handleNoteDeleted(String noteId) {
    if (!_isActive) return;
    
    _logger.info('Handling note deleted: $noteId');
    if (_notesMap.containsKey(noteId)) {
      _notesMap.remove(noteId);
      _logger.info('Removed note $noteId from local state');
      
      // Also unsubscribe from this note's events
      _webSocketService.unsubscribe('note', id: noteId);
      
      notifyListeners();
    } else {
      _logger.info('Note $noteId not found in local state, nothing to remove');
    }
  }

  @override
  void dispose() {
    _resetSubscription?.cancel();
    _connectionSubscription?.cancel();
    
    // Remove event listeners
    _webSocketService.removeEventListener('event', 'note.updated');
    _webSocketService.removeEventListener('event', 'note.created');
    _webSocketService.removeEventListener('event', 'note.deleted');
    
    super.dispose();
  }
}
