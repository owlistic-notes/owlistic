import 'dart:async';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../models/notebook.dart';
import '../services/trash_service.dart';
import '../services/auth_service.dart';
import '../services/base_service.dart';
import 'websocket_provider.dart';
import '../utils/logger.dart';

class TrashProvider with ChangeNotifier {
  final Logger _logger = Logger('TrashProvider');
  
  List<Note> _trashedNotes = [];
  List<Notebook> _trashedNotebooks = [];
  bool _isLoading = false;
  WebSocketProvider? _webSocketProvider;
  bool _isActive = false;
  
  // Services
  final TrashService _trashService;
  final AuthService _authService;
  
  // Constructor with dependency injection
  TrashProvider({
    TrashService? trashService,
    AuthService? authService
  }) : _trashService = trashService ?? ServiceLocator.get<TrashService>(),
       _authService = authService ?? ServiceLocator.get<AuthService>();
  
  // Getters
  List<Note> get trashedNotes => _trashedNotes;
  List<Notebook> get trashedNotebooks => _trashedNotebooks;
  bool get isLoading => _isLoading;
  
  // Reset state on logout
  void resetState() {
    _logger.info('Resetting TrashProvider state');
    _trashedNotes = [];
    _trashedNotebooks = [];
    _isActive = false;
    notifyListeners();
  }
  
  // Activate/deactivate pattern to manage resource usage
  void activate() {
    _isActive = true;
    _logger.info('TrashProvider activated');
    fetchTrashedItems(); // Load data when activated
  }
  
  void deactivate() {
    _isActive = false;
    _logger.info('TrashProvider deactivated');
  }
  
  // Set the WebSocketProvider
  void setWebSocketProvider(WebSocketProvider provider) {
    if (_webSocketProvider == provider) return;
    
    // Unregister from previous provider if exists
    if (_webSocketProvider != null) {
      _webSocketProvider!.removeEventListener('event', 'note.deleted');
      _webSocketProvider!.removeEventListener('event', 'notebook.deleted');
      _webSocketProvider!.removeEventListener('event', 'note.restored');
      _webSocketProvider!.removeEventListener('event', 'notebook.restored');
      
      // Unsubscribe from events
      if (_webSocketProvider!.isConnected) {
        _webSocketProvider?.unsubscribeFromEvent('note.deleted');
        _webSocketProvider?.unsubscribeFromEvent('notebook.deleted');
        _webSocketProvider?.unsubscribeFromEvent('note.restored');
        _webSocketProvider?.unsubscribeFromEvent('notebook.restored');
      }
    }
    
    _webSocketProvider = provider;
    
    // Register for events that would affect the trash
    provider.addEventListener('event', 'note.deleted', _handleItemDeleted);
    provider.addEventListener('event', 'notebook.deleted', _handleItemDeleted);
    provider.addEventListener('event', 'note.restored', _handleItemRestored);
    provider.addEventListener('event', 'notebook.restored', _handleItemRestored);
    
    // Subscribe to these events using the correct pattern
    if (provider.isConnected) {
      provider.subscribeToEvent('note.deleted');
      provider.subscribeToEvent('notebook.deleted');
      provider.subscribeToEvent('note.restored');
      provider.subscribeToEvent('notebook.restored');
    }
    
    _logger.info('WebSocketProvider set for TrashProvider');
  }
  
  // WebSocket event handlers
  void _handleItemDeleted(Map<String, dynamic> message) {
    _logger.info('Item deletion detected, refreshing trash');
    if (_isActive) {
      fetchTrashedItems();
    }
  }
  
  void _handleItemRestored(Map<String, dynamic> message) {
    _logger.info('Item restoration detected, refreshing trash');
    if (_isActive) {
      fetchTrashedItems();
    }
  }
  
  // Fetch all trashed items with user filtering
  Future<void> fetchTrashedItems() async {
    if (!_isActive) return;
    
    // Get current user ID for filtering
    final currentUser = await _authService.getUserProfile();
    if (currentUser == null) {
      _logger.warning('Cannot fetch trash: No authenticated user');
      return;
    }
    
    _isLoading = true;
    notifyListeners();
    
    try {
      // Pass user ID for proper filtering
      final trashedItems = await _trashService.fetchTrashedItems(userId: currentUser.id);
      
      // Convert List<dynamic> to List<Note> and List<Notebook>
      _trashedNotes = (trashedItems['notes'] as List).cast<Note>();
      _trashedNotebooks = (trashedItems['notebooks'] as List).cast<Notebook>();
      
      _logger.info('Fetched ${_trashedNotes.length} trashed notes and ${_trashedNotebooks.length} trashed notebooks');
      
      _isLoading = false;
      notifyListeners();
    } catch (error) {
      _logger.error('Error fetching trashed items', error);
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Restore an item from trash
  Future<void> restoreItem(String type, String id) async {
    try {
      // Get current user ID for the API request
      final currentUser = await _authService.getUserProfile();
      if (currentUser == null) {
        _logger.warning('Cannot restore item: No authenticated user');
        throw Exception('User is not authenticated');
      }
      
      await _trashService.restoreItem(type, id, userId: currentUser.id);
      
      _logger.info('Restored $type with ID: $id');
      
      // Update local data immediately for responsiveness
      if (type == 'note') {
        _trashedNotes.removeWhere((note) => note.id == id);
      } else if (type == 'notebook') {
        _trashedNotebooks.removeWhere((notebook) => notebook.id == id);
      }
      
      notifyListeners();
    } catch (error) {
      _logger.error('Error restoring item from trash', error);
      rethrow;
    }
  }
  
  // Permanently delete an item from trash
  Future<void> permanentlyDeleteItem(String type, String id) async {
    try {
      // Get current user ID for the API request
      final currentUser = await _authService.getUserProfile();
      if (currentUser == null) {
        _logger.warning('Cannot delete item: No authenticated user');
        throw Exception('User is not authenticated');
      }
      
      await _trashService.permanentlyDeleteItem(type, id, userId: currentUser.id);
      
      _logger.info('Permanently deleted $type with ID: $id');
      
      // Update local data immediately for responsiveness
      if (type == 'note') {
        _trashedNotes.removeWhere((note) => note.id == id);
      } else if (type == 'notebook') {
        _trashedNotebooks.removeWhere((notebook) => notebook.id == id);
      }
      
      notifyListeners();
    } catch (error) {
      _logger.error('Error permanently deleting item', error);
      rethrow;
    }
  }
  
  // Empty the entire trash
  Future<void> emptyTrash() async {
    try {
      // Get current user ID for the API request
      final currentUser = await _authService.getUserProfile();
      if (currentUser == null) {
        _logger.warning('Cannot empty trash: No authenticated user');
        throw Exception('User is not authenticated');
      }
      
      await _trashService.emptyTrash(userId: currentUser.id);
      
      _logger.info('Emptied trash');
      
      // Clear local data
      _trashedNotes = [];
      _trashedNotebooks = [];
      
      notifyListeners();
    } catch (error) {
      _logger.error('Error emptying trash', error);
      rethrow;
    }
  }
  
  @override
  void dispose() {
    if (_webSocketProvider != null) {
      _webSocketProvider!.removeEventListener('event', 'note.deleted');
      _webSocketProvider!.removeEventListener('event', 'notebook.deleted');
      _webSocketProvider!.removeEventListener('event', 'note.restored');
      _webSocketProvider!.removeEventListener('event', 'notebook.restored');
      
      // Unsubscribe from events
      if (_webSocketProvider!.isConnected) {
        _webSocketProvider?.unsubscribeFromEvent('note.deleted');
        _webSocketProvider?.unsubscribeFromEvent('notebook.deleted');
        _webSocketProvider?.unsubscribeFromEvent('note.restored');
        _webSocketProvider?.unsubscribeFromEvent('notebook.restored');
      }
    }
    super.dispose();
  }
}
