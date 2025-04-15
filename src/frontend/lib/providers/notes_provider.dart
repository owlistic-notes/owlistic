import 'dart:async';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/api_service.dart';
import 'websocket_provider.dart';
import '../models/subscription.dart';

class NotesProvider with ChangeNotifier {
  List<Note> _notes = [];
  bool _isLoading = false;
  WebSocketProvider? _webSocketProvider;
final Set<String> _activeNoteIds = {};

  // Getters
  List<Note> get notes => [..._notes];
  bool get isLoading => _isLoading;
  List<Note> get recentNotes => _notes.length > 3 ? _notes.sublist(0, 3) : _notes;
  
  Note? getNoteById(String id) {
    try {
      return _notes.firstWhere((note) => note.id == id);
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
    
    // Register for relevant events
    provider.addEventListener('event', 'note.updated', _handleNoteUpdate);
    provider.addEventListener('event', 'note.created', _handleNoteCreate);
    provider.addEventListener('event', 'note.deleted', _handleNoteDelete);
  }

  // Mark a note as active/inactive
  void activateNote(String noteId) => _activeNoteIds.add(noteId);
  void deactivateNote(String noteId) => _activeNoteIds.remove(noteId);

  // Handle note update events
  void _handleNoteUpdate(Map<String, dynamic> message) {
    String? noteId = null;
  
    // Try to extract note_id from the nested structure
    if (message.containsKey('payload')) {
      final payload = message['payload'];
      
      // Check for double-nested payload structure
      if (payload is Map<String, dynamic> && payload.containsKey('payload')) {
        final innerPayload = payload['payload'];
        
        if (innerPayload is Map<String, dynamic> && innerPayload.containsKey('data')) {
          final data = innerPayload['data'];
          
          if (data is Map<String, dynamic> && data.containsKey('note_id')) {
            noteId = data['note_id'].toString();
          }
        }
      } 
      // Also check regular structure
      else if (payload is Map<String, dynamic> && payload.containsKey('data')) {
        final data = payload['data'];
        
        if (data is Map<String, dynamic> && data.containsKey('note_id')) {
          noteId = data['note_id'].toString();
        }
      }
    }
    
    if (noteId != null) {
      _fetchSingleNote(noteId);
    } else {
      print('NotesProvider: Could not find note_id in update message');
    }
  }

  // Handle note create events
  void _handleNoteCreate(Map<String, dynamic> message) {
    print('NotesProvider: Received note.created event');
    
    String? noteId = null;
    
    // Get the note_id from the deeply nested structure
    if (message.containsKey('payload')) {
      final payload = message['payload'];
      
      // Check for double-nested payload structure
      if (payload is Map<String, dynamic> && payload.containsKey('payload')) {
        final innerPayload = payload['payload'];
        
        if (innerPayload is Map<String, dynamic> && innerPayload.containsKey('data')) {
          final data = innerPayload['data'];
          
          if (data is Map<String, dynamic> && data.containsKey('note_id')) {
            noteId = data['note_id'].toString();
            print('NotesProvider: Found note_id in nested structure: $noteId');
          }
        }
      } 
      // Also check regular structure
      else if (payload is Map<String, dynamic> && payload.containsKey('data')) {
        final data = payload['data'];
        
        if (data is Map<String, dynamic> && data.containsKey('note_id')) {
          noteId = data['note_id'].toString();
          print('NotesProvider: Found note_id in regular structure: $noteId');
        }
      }
    }
    
    if (noteId != null) {
      // Add a short delay to avoid race condition with database
      Future.delayed(Duration(milliseconds: 500), () {
       if (noteId != null) {
          _fetchSingleNote(noteId);
        } else {
          print('NotesProvider: Could not find note_id in update message');
        }
      });
    } else {
      print('NotesProvider: Could not find note_id in message');
    }
  }
  
  // Handle note delete events
  void _handleNoteDelete(Map<String, dynamic> message) {
    // Get the note_id from payload.data
    if (message.containsKey('payload') && 
        message['payload'] is Map<String, dynamic> &&
        message['payload']['data'] is Map<String, dynamic>) {
      
      final data = message['payload']['data'];
      final noteId = data['note_id'];
      
      if (noteId != null) {
        // Remove from local state if it exists
        final index = _notes.indexWhere((note) => note.id == noteId.toString());
        if (index != -1) {
          _notes.removeAt(index);
          notifyListeners();
        }
      }
    }
  }

  // Fetch a single note by ID
  Future<Note> _fetchSingleNote(String noteId) async {
    try {
      final note = await ApiService.getNote(noteId);
      
      // Check if this note already exists in our list
      final index = _notes.indexWhere((n) => n.id == noteId);
      if (index != -1) {
        _notes[index] = note;
      } else {
        _notes.add(note);
      }
      
      // Subscribe to this note
      _webSocketProvider?.subscribe('note', id: noteId);
      
      notifyListeners();
      return note;
    } catch (error) {
      print('NotesProvider: Error fetching note $noteId: $error');
      throw error;
    }
  }

  // Fetch all notes and subscribe to global note events
  Future<void> fetchNotes({int page = 1, int pageSize = 20}) async {
    if (_isLoading) return;
    
    _isLoading = true;
    notifyListeners();

    try {
      // Fetch notes with pagination
      final fetchedNotes = await ApiService.fetchNotes(page: page, pageSize: pageSize);
      
      if (page == 1) {
        // First page, replace existing data
        _notes = fetchedNotes;
      } else {
        // Subsequent page, append to existing data
        _notes.addAll(fetchedNotes);
      }
      
      // Subscribe to note events
      if (_webSocketProvider != null) {
        // Prepare subscription batch
        final subscriptions = <Subscription>[
          Subscription('note'),
        ];
        
        // Add individual note subscriptions
        for (var i = 0; i < _notes.length && i < 20; i++) {
          subscriptions.add(Subscription('note', id: _notes[i].id));
        }
        
        // Batch subscribe
        await _webSocketProvider!.batchSubscribe(subscriptions);
      }
    } catch (error) {
      print('NotesProvider: Error fetching notes: $error');
      // Only clear on first page error
      if (page == 1) _notes = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  // Create a new note
  Future<void> createNote(String notebookId, String title) async {
    try {
      final note = await ApiService.createNote(notebookId, title);
      _notes.add(note);
      
      // Subscribe to this note
      _webSocketProvider?.subscribe('note', id: note.id);
      
      notifyListeners();
    } catch (error) {
      print('NotesProvider: Error creating note: $error');
      rethrow;
    }
  }

  // Delete a note
  Future<void> deleteNote(String id) async {
    try {
      await ApiService.deleteNote(id);
      _notes.removeWhere((note) => note.id == id);
      
      // Unsubscribe from this note
      _webSocketProvider?.unsubscribe('note', id: id);
      
      notifyListeners();
    } catch (error) {
      print('NotesProvider: Error deleting note: $error');
      rethrow;
    }
  }

  // Update a note via WebSocket
  void updateNote(String id, String title) {
    // Send update via WebSocket
    _webSocketProvider?.sendNoteUpdate(id, title);
    
    // Optimistically update local state
    final index = _notes.indexWhere((note) => note.id == id);
    if (index != -1) {
      final updatedNote = Note(
        id: _notes[index].id,
        title: title,
        notebookId: _notes[index].notebookId,
        userId: _notes[index].userId,
        blocks: _notes[index].blocks,
      );
      _notes[index] = updatedNote;
      notifyListeners();
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
