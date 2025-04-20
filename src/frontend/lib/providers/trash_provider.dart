import 'dart:async';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../models/notebook.dart';
import '../services/api_service.dart';
import 'websocket_provider.dart';
import '../utils/logger.dart';

class TrashProvider with ChangeNotifier {
  final Logger _logger = Logger('TrashProvider');
  
  List<Note> _trashedNotes = [];
  List<Notebook> _trashedNotebooks = [];
  bool _isLoading = false;
  WebSocketProvider? _webSocketProvider;
  bool _isActive = false;
  
  // Getters
  List<Note> get trashedNotes => _trashedNotes;
  List<Notebook> get trashedNotebooks => _trashedNotebooks;
  bool get isLoading => _isLoading;
  
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
    _webSocketProvider = provider;
    
    // Register for events that would affect the trash
    provider.addEventListener('event', 'note.deleted', _handleItemDeleted);
    provider.addEventListener('event', 'notebook.deleted', _handleItemDeleted);
    provider.addEventListener('event', 'note.restored', _handleItemRestored);
    provider.addEventListener('event', 'notebook.restored', _handleItemRestored);
    
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
  
  // Fetch all trashed items
  Future<void> fetchTrashedItems() async {
    if (!_isActive) return;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      final trashedItems = await ApiService.fetchTrashedItems();
      
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
      await ApiService.restoreItem(type, id);
      
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
      await ApiService.permanentlyDeleteItem(type, id);
      
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
      await ApiService.emptyTrash();
      
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
    }
    super.dispose();
  }
}
