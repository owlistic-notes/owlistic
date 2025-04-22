import 'dart:async';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/api_service.dart';
import 'websocket_provider.dart';
import '../utils/websocket_message_parser.dart';
import '../utils/logger.dart';

class NotesProvider with ChangeNotifier {
  final Logger _logger = Logger('NotesProvider');
  // Use a Map instead of a List to prevent duplicates
  final Map<String, Note> _notesMap = {};
  bool _isLoading = false;
  WebSocketProvider? _webSocketProvider;
  final Set<String> _activeNoteIds = {};

  // Getters
  List<Note> get notes => _notesMap.values.toList();
  
  // Fixed: Changed updatedAt to a different sorting method since Note doesn't have updatedAt
  List<Note> get recentNotes {
    final notesList = _notesMap.values.toList();
    // Sort by ID for now, or any other field available in your Note model
    // Assuming newer notes have higher IDs or you can modify this to suit your model
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

  // Set the WebSocketProvider and register event listeners
  void setWebSocketProvider(WebSocketProvider provider) {
    // Skip if the provider is the same
    if (_webSocketProvider == provider) return;
    
    // Unregister from old provider if exists
    if (_webSocketProvider != null) {
      _webSocketProvider?.removeEventListener('event', 'note.updated');
      _webSocketProvider?.removeEventListener('event', 'note.created');
      _webSocketProvider?.removeEventListener('event', 'note.deleted');
    }
    
    _webSocketProvider = provider;
    
    // Register for standardized resource.action events
    provider.addEventListener('event', 'note.updated', _handleNoteUpdate);
    provider.addEventListener('event', 'note.created', _handleNoteCreate);
    provider.addEventListener('event', 'note.deleted', _handleNoteDelete);
  }

  // Mark a note as active/inactive
  void activateNote(String noteId) => _activeNoteIds.add(noteId);
  void deactivateNote(String noteId) => _activeNoteIds.remove(noteId);

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
          ApiService.getNote(noteId).then((newNote) {
            // Only add if provider is active and note is not deleted
            if (_isActive && newNote.deletedAt == null) {
              _notesMap[noteId] = newNote;
              _logger.info('Added new note $noteId to list');
              
              // Subscribe to this note
              _webSocketProvider?.subscribe('note', id: newNote.id);
              
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
      final note = await ApiService.getNote(noteId);
      
      // Check if this note already exists in our list
      if (_notesMap.containsKey(noteId)) {
        _notesMap[noteId] = note;
      } else {
        _notesMap[noteId] = note;
      }
      
      // Subscribe to this note
      _webSocketProvider?.subscribe('note', id: noteId);
      
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
      final notebook = await _fetchSingleNote(noteId);
      return notebook;
    } catch (error) {
      _logger.error('Error in fetchNotebookById: $error');
      return null;
    }
  }

  // Fetch notes with pagination and duplicate prevention
  Future<void> fetchNotes({int page = 1, List<String>? excludeIds}) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Fetch notes from API
      final response = await ApiService.fetchNotes(page: page);
      final List<Note> fetchedNotes = response;
      
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
      }
      
      _isLoading = false;
      notifyListeners();
    } catch (error) {
      _isLoading = false;
      notifyListeners();
      throw error;
    }
  }

  // Add single note from websocket event
  Future<void> addNoteFromEvent(String noteId) async {
    if (!_isActive) return;
    
    try {
      // Only fetch if we don't already have this note
      if (!_notesMap.containsKey(noteId)) {
        _logger.info('Fetching note $noteId from event');
        
        final note = await ApiService.getNote(noteId);
        
        // Only add if the note is not deleted
        if (note.deletedAt == null) {
          _notesMap[noteId] = note;
          
          // Subscribe to this note
          _webSocketProvider?.subscribe('note', id: note.id);
          
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

  // Create a new note - no optimistic updates
  Future<Note?> createNote(String notebookId, String title) async {
    try {
      // Create note on server
      final note = await ApiService.createNote(notebookId, title);
      
      // Subscribe to this note
      _webSocketProvider?.subscribe('note', id: note.id);
      
      _logger.info('Created note: $title, waiting for event');
      return note;
    } catch (error) {
      _logger.error('Error creating note: $error');
      rethrow;
    }
  }

  // Delete a note - no optimistic updates
  Future<void> deleteNote(String id) async {
    try {
      // Perform the delete operation on server
      await ApiService.deleteNote(id);
      
      // Unsubscribe from this note
      _webSocketProvider?.unsubscribe('note', id: id);
      
      _logger.info('Deleted note: $id, waiting for event');
      notifyListeners();
    } catch (error) {
      _logger.error('Error deleting note: $error');
      rethrow;
    }
  }

  // Update a note via WebSocket - no optimistic updates
  void updateNote(String id, String title) {
    // Simply send update via WebSocket and wait for event to come back
    _webSocketProvider?.sendNoteUpdate(id, title);
    _logger.info('Sent note title update to server: $title');
  }

  // Activate/deactivate provider state management
  bool _isActive = false;

  void activate() {
    _isActive = true;
    _logger.info('NotesProvider activated');
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
      _webSocketProvider?.unsubscribe('note', id: noteId);
      
      notifyListeners();
    } else {
      _logger.info('Note $noteId not found in local state, nothing to remove');
    }
  }

  @override
  void dispose() {
    // Unregister event handlers
    if (_webSocketProvider != null) {
      _webSocketProvider?.removeEventListener('event', 'note.updated');
      _webSocketProvider?.removeEventListener('event', 'note.created');
      _webSocketProvider?.removeEventListener('event', 'note.deleted');
    }
    super.dispose();
  }
}
