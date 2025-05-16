import 'dart:async';
import 'package:flutter/material.dart';
import 'package:owlistic/utils/document_builder.dart';
import 'package:owlistic/viewmodel/notes_viewmodel.dart';
import 'package:owlistic/models/note.dart';
import 'package:owlistic/services/note_service.dart';
import 'package:owlistic/services/auth_service.dart';
import 'package:owlistic/services/websocket_service.dart';
import 'package:owlistic/services/base_service.dart';
import 'package:owlistic/utils/websocket_message_parser.dart';
import 'package:owlistic/utils/logger.dart';
import 'package:owlistic/services/block_service.dart';
import 'package:owlistic/services/app_state_service.dart';
import 'package:super_editor_markdown/super_editor_markdown.dart';

class NotesProvider with ChangeNotifier implements NotesViewModel {
  final Logger _logger = Logger('NotesProvider');
  // Use a Map instead of a List to prevent duplicates
  final Map<String, Note> _notesMap = {};
  bool _isLoading = false;
  bool _isActive = false; // For lifecycle management
  bool _isInitialized = false;
  final Set<String> _activeNoteIds = {};
  String? _errorMessage;
  int _updateCount = 0;
  
  // Services
  final NoteService _noteService;
  final AuthService _authService;
  final BlockService _blockService;
  final WebSocketService _webSocketService;
  final AppStateService _appStateService = AppStateService();
  
  // Subscriptions
  StreamSubscription? _resetSubscription;
  StreamSubscription? _connectionSubscription;

  // Constructor with dependency injection - add WebSocketService parameter
  NotesProvider({
    NoteService? noteService, 
    AuthService? authService, 
    required BlockService blockService,
    required WebSocketService webSocketService
  }) : _noteService = noteService ?? ServiceLocator.get<NoteService>(),
      _authService = authService ?? ServiceLocator.get<AuthService>(),
      _blockService = blockService,
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
      }
    });

    // Mark initialization as complete
    _isInitialized = true;
  }

  // Getters
  @override
  List<Note> get notes => _notesMap.values.toList();
  
  // Fixed: Changed updatedAt to a different sorting method since Note doesn't have updatedAt
  @override
  List<Note> get recentNotes {
    final notesList = _notesMap.values.toList();
    // Sort by ID for now, or any other field available in your Note model
    notesList.sort((a, b) => b.id.compareTo(a.id));
    return notesList.take(5).toList();
  }
  
  @override
  bool get isEmpty => _notesMap.isEmpty;
  @override
  int get updateCount => _updateCount;
  
  Note? getNoteById(String id) {
    try {
      return _notesMap[id];
    } catch (e) {
      return null;
    }
  }

  // Reset state on logout
  @override
  void resetState() {
    _logger.info('Resetting NotesProvider state');
    _notesMap.clear();
    _activeNoteIds.clear();
    _isActive = false;
    notifyListeners();
  }

  // Initialize WebSocket event listeners
  void _initializeEventListeners() {
    _webSocketService.addEventListener('event', 'note.created', _handleNoteCreate);
    _webSocketService.addEventListener('event', 'note.updated', _handleNoteUpdate);
    _webSocketService.addEventListener('event', 'note.deleted', _handleNoteDelete);
  }

  // Subscribe to events
  void _subscribeToEvents() {
    _webSocketService.subscribeToEvent('note.updated');
    _webSocketService.subscribeToEvent('note.created');
    _webSocketService.subscribeToEvent('note.deleted');
  }

  // Mark a note as active/inactive
  @override
  void activateNote(String noteId) {
    _activeNoteIds.add(noteId);
    _webSocketService.subscribe('note', id: noteId);
    _logger.debug('Note $noteId activated');
  }
  
  @override
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
    try {
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);

      if (noteId != null) {
        _logger.info('Handling note.created event for note ID: $noteId');
        fetchNoteById(noteId); // Fetch and add the new note
      }
    } catch (e) {
      _logger.error('Error handling note.created event', e);
    }
  }
  
  // Handle note delete events
  void _handleNoteDelete(Map<String, dynamic> message) {
    try {
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);

      if (noteId != null) {
        _logger.info('Handling note.deleted event for note ID: $noteId');
        handleNoteDeleted(noteId); // Remove the note from the local state
      }
    } catch (e) {
      _logger.error('Error handling note.deleted event', e);
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
      rethrow;
    }
  }

  // Public method to fetch a single note by ID
  @override
  Future<Note?> fetchNoteById(String noteId) async {
    try {
      _logger.info('Fetching note by ID: $noteId');
      
      // Fetch note from API service
      final note = await _noteService.getNote(noteId);
      _logger.debug('Successfully fetched note: ${note.title}');
      
      // Update our local map with the fetched note
      _notesMap[noteId] = note;
      
      // If this note is active, subscribe to it via WebSocket
      if (_activeNoteIds.contains(noteId)) {
        _webSocketService.subscribe('note', id: noteId);
      }
      
      // Always notify listeners to update UI
      notifyListeners();
      return note;
    } catch (e) {
      _logger.error('Error fetching note by id: $noteId', e);
      return null;
    }
  }

  // Fetch notes with pagination and proper user filtering
  // Updated to match interface signature
  @override
  Future<List<Note>> fetchNotes({
    String? notebookId, 
    int page = 1, 
    int pageSize = 20,
    List<String>? excludeIds
  }) async {
    // Check if user is logged in
    final currentUser = await _authService.getUserProfile();
    if (currentUser == null) {
      _logger.warning('Cannot fetch notes: No authenticated user');
      return [];
    }

    _isLoading = true;
    notifyListeners();
    
    try {
      // Fetch notes from API with notebook filter
      final fetchedNotes = await _noteService.fetchNotes(
        notebookId: notebookId,
        page: page,
        pageSize: pageSize
      );
      
      // Keep track of existing IDs if not starting fresh
      final existingIds = page > 1 ? _notesMap.keys.toSet() : <String>{};
      
      // Update the map without replacing existing notes if first page
      if (page == 1 && notebookId != null) {
        // Only clear notes associated with this notebook
        _notesMap.removeWhere((_, note) => note.notebookId == notebookId);
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
      _updateCount++;
      notifyListeners();
      return fetchedNotes;
    } catch (error) {
      _logger.error('Error fetching notes', error);
      _errorMessage = 'Failed to load notes: ${error.toString()}';
      _isLoading = false;
      notifyListeners();
      return [];
    }
  }

  // Helper method to get notes by notebook ID
  @override
  List<Note> getNotesByNotebookId(String notebookId) {
    return _notesMap.values
      .where((note) => note.notebookId == notebookId)
      .toList();
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

  // Create a new note - updated to match interface signature
  @override
  Future<Note> createNote(String title, String? notebookId) async {
    try {
      if (notebookId == null) {
        throw Exception("Notebook ID is required to create a note");
      }
      
      // Create note on server via REST API
      final note = await _noteService.createNote(notebookId, title);
      
      // Add to local state
      _notesMap[note.id] = note;
      
      // Only subscribe to WebSocket events for this note
      _webSocketService.subscribe('note', id: note.id);
      
      // Notify listeners about the new note
      _updateCount++;
      notifyListeners();
      
      _logger.info('Created note: $title with ID: ${note.id}');
      return note;
    } catch (error) {
      _logger.error('Error creating note: $error');
      _errorMessage = 'Failed to create note: ${error.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  // Delete a note - ensure API call and notification
  @override
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

  // Update a note using API call - updated to use enhanced service method 
  @override
  Future<Note> updateNote(String id, String title, {String? notebookId}) async {
    try {
      _logger.info('Updating note $id title to: $title via API');
      
      // Build query parameters for tracking update operation
      final queryParams = <String, dynamic>{};
      if (notebookId != null) {
        queryParams['notebook_id'] = notebookId;
      }
      
      // Update note via REST API call with query parameters
      final updatedNote = await _noteService.updateNote(
        id, 
        title,
        queryParams: queryParams
      );
      
      // Update local state if we have this note
      if (_notesMap.containsKey(id)) {
        _notesMap[id] = updatedNote;
        _logger.info('Updated note $id title to: $title');
        
        _updateCount++;
        // Always notify listeners to update UI
        notifyListeners();
      }
      
      return updatedNote;
    } catch (error) {
      _logger.error('Error updating note: $error');
      _errorMessage = 'Failed to update note: ${error.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  /// Move a note from one notebook to another by updating its notebook_id
  @override
  Future<void> moveNote(String noteId, String newNotebookId) async {
    try {
      _logger.info('Moving note $noteId to notebook $newNotebookId');
      _isLoading = true;
      notifyListeners();

      // Use the note service to update the notebook_id via a PUT request
      // Pass additional query parameters for tracking the move operation
      final updatedNote = await _noteService.updateNote(
        noteId, 
        null,
        notebookId: newNotebookId,
      );
      
      // Update the note in our local state
      if (_notesMap.containsKey(noteId)) {
        _notesMap[noteId] = updatedNote;
        _logger.info('Successfully moved note $noteId to notebook $newNotebookId');
      }
      
      _updateCount++;
      notifyListeners();
    } catch (e) {
      _logger.error('Error moving note', e);
      _errorMessage = 'Failed to move note: ${e.toString()}';
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void activate() {
    _isActive = true;
    _logger.info('NotesProvider activated');
    
    // Subscribe to events when activated
    if (_webSocketService.isConnected) {
      _subscribeToEvents();
    }
  }

  @override
  void deactivate() {
    _isActive = false;
    _logger.info('NotesProvider deactivated');
  }

  // Add this method to handle note deletion events with more robust implementation
  @override
  void handleNoteDeleted(String noteId) {
    _logger.info('Handling note deleted: $noteId');
    
    if (_notesMap.containsKey(noteId)) {
      _notesMap.remove(noteId);
      _logger.info('Removed note $noteId from local state');
      
      // Also unsubscribe from this note's events
      _webSocketService.unsubscribe('note', id: noteId);
      
      // Always notify listeners to update UI
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
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  @override
  Future<Note?> importMarkdownFile(String content, String fileName, String notebookId) async {
    try {
      _logger.info('Importing markdown file: $fileName to notebook: $notebookId');
      
      if (notebookId.isEmpty) {
        throw Exception("Notebook ID is required to import a note");
      }
      
      // Extract title from filename (remove .md extension if present)
      String title = fileName;
      if (title.toLowerCase().endsWith('.md')) {
        title = title.substring(0, title.length - 3);
      }
      
      // Create the note first
      final note = await _noteService.createNote(notebookId, title);
      _logger.debug('Created note: ${note.id} for markdown import');
      
      final documentBuilder = DocumentBuilder();

      // Create blocks for each node
      final document = documentBuilder.deserializeMarkdownContent(content);

      // Create blocks for each node
      int order = 0;
      for (final node in document) {
        try {
          final blockContent = documentBuilder.buildBlockContent(node);
          
          final blockType = blockContent['type'];
          final payload = {
            "metadata": blockContent['metadata'],
            "content": blockContent['content'],
          };

          // Create block through BlockService
          await _blockService.createBlock(
            note.id,
            payload,
            blockType,
            (order + 1) * 1000.0  // Use increasing order with gaps
          );
          
          order++;
        } catch (e) {
          _logger.error('Error creating block for imported markdown: $e');
        }
      }
      
      // Add note to local state
      _notesMap[note.id] = note;
      _updateCount++;
      notifyListeners();
      
      return note;
    } catch (error) {
      _logger.error('Error importing markdown file', error);
      _errorMessage = 'Failed to import markdown: ${error.toString()}';
      notifyListeners();
      return null;
    }
  }
  
  @override
  Future<String> exportNoteToMarkdown(String noteId) async {
    try {
      _logger.info('Exporting note $noteId to markdown');
      
      // Fetch note if not already in memory
      Note? note = _notesMap[noteId];
      note = await fetchNoteById(noteId);

      if (note == null) {
        throw Exception("Note not found");
      }
      
      // Fetch all blocks for the note to ensure we have the latest data
      final blocks = await _blockService.fetchBlocksForNote(noteId);
      
      // Create a document from the blocks
      final documentBuilder = DocumentBuilder();
      
      // Convert blocks to document nodes
      documentBuilder.populateDocumentFromBlocks(blocks);
      
      // Serialize document to markdown
      final markdown = serializeDocumentToMarkdown(
        documentBuilder.document,
        syntax: MarkdownSyntax.normal
      );
      
      _logger.debug('Note exported to markdown successfully');
      return markdown;
    } catch (error) {
      _logger.error('Error exporting note to markdown', error);
      throw Exception('Failed to export note: ${error.toString()}');
    }
  }
}
