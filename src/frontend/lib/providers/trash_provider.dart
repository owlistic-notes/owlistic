import 'dart:async';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../models/notebook.dart';
import '../services/trash_service.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import '../utils/logger.dart';
import '../services/app_state_service.dart';
import '../viewmodel/trash_viewmodel.dart';

class TrashProvider with ChangeNotifier implements TrashViewModel {
  final Logger _logger = Logger('TrashProvider');
  
  List<Note> _trashedNotes = [];
  List<Notebook> _trashedNotebooks = [];
  bool _isLoading = false;
  bool _isActive = false;
  bool _isInitialized = false;
  String? _errorMessage;
  
  // Services
  final TrashService _trashService;
  final AuthService _authService;
  final WebSocketService _webSocketService;
  
  // Add subscription for app state changes
  StreamSubscription? _resetSubscription;
  StreamSubscription? _connectionSubscription;
  final AppStateService _appStateService = AppStateService();
  
  // Constructor with dependency injection - add WebSocketService parameter
  TrashProvider({
    required TrashService trashService,
    required AuthService authService,
    required WebSocketService webSocketService
  }) : _trashService = trashService,
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
      }
    });
    
    _isInitialized = true;
  }
  
  // Initialize WebSocket event listeners
  void _initializeEventListeners() {
    _webSocketService.addEventListener('event', 'note.deleted', _handleItemDeleted);
    _webSocketService.addEventListener('event', 'notebook.deleted', _handleItemDeleted);
    _webSocketService.addEventListener('event', 'note.restored', _handleItemRestored);
    _webSocketService.addEventListener('event', 'notebook.restored', _handleItemRestored);
  }
  
  // Subscribe to events
  void _subscribeToEvents() {
    _webSocketService.subscribeToEvent('note.deleted');
    _webSocketService.subscribeToEvent('notebook.deleted');
    _webSocketService.subscribeToEvent('note.restored');
    _webSocketService.subscribeToEvent('notebook.restored');
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
  
  // TrashPresenter implementation
  @override
  List<Note> get trashedNotes => _trashedNotes;
  
  @override
  List<Notebook> get trashedNotebooks => _trashedNotebooks;
  
  // Reset state on logout
  @override
  void resetState() {
    _logger.info('Resetting TrashProvider state');
    _trashedNotes = [];
    _trashedNotebooks = [];
    _isActive = false;
    notifyListeners();
  }
  
  // Activate/deactivate pattern to manage resource usage
  @override
  void activate() {
    _isActive = true;
    _logger.info('TrashProvider activated');
    
    // Subscribe to events when activated
    if (_webSocketService.isConnected) {
      _subscribeToEvents();
    }
    
    fetchTrashedItems(); // Load data when activated
  }
  
  @override
  void deactivate() {
    _isActive = false;
    _logger.info('TrashProvider deactivated');
  }
  
  // WebSocket event handlers
  void _handleItemDeleted(Map<String, dynamic> message) {
    // Handle item deletion
  }
  
  void _handleItemRestored(Map<String, dynamic> message) {
    // Handle item restoration
  }
  
  // Fetch all trashed items with user filtering
  @override
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
      final trashedItems = await _trashService.fetchTrashedItems();
      
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
  @override
  Future<void> restoreItem(String type, String id) async {
    try {
      // Get current user ID for the API request
      final currentUser = await _authService.getUserProfile();
      if (currentUser == null) {
        _logger.warning('Cannot restore item: No authenticated user');
        throw Exception('User is not authenticated');
      }
      
      await _trashService.restoreItem(type, id);
      
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
  @override
  Future<void> permanentlyDeleteItem(String type, String id) async {
    try {
      // Get current user ID for the API request
      final currentUser = await _authService.getUserProfile();
      if (currentUser == null) {
        _logger.warning('Cannot delete item: No authenticated user');
        throw Exception('User is not authenticated');
      }
      
      await _trashService.permanentlyDeleteItem(type, id);
      
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
  @override
  Future<void> emptyTrash() async {
    try {
      // Get current user ID for the API request
      final currentUser = await _authService.getUserProfile();
      if (currentUser == null) {
        _logger.warning('Cannot empty trash: No authenticated user');
        throw Exception('User is not authenticated');
      }
      
      await _trashService.emptyTrash();
      
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
    _resetSubscription?.cancel();
    _connectionSubscription?.cancel();
    
    // Remove event listeners
    _webSocketService.removeEventListener('event', 'note.deleted');
    _webSocketService.removeEventListener('event', 'notebook.deleted');
    _webSocketService.removeEventListener('event', 'note.restored');
    _webSocketService.removeEventListener('event', 'notebook.restored');
    
    super.dispose();
  }
}
