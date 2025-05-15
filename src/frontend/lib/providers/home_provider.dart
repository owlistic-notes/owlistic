import 'package:flutter/material.dart';
import 'package:owlistic/models/note.dart';
import 'package:owlistic/models/notebook.dart';
import 'package:owlistic/models/task.dart';
import 'package:owlistic/models/user.dart';
import 'package:owlistic/services/auth_service.dart';
import 'package:owlistic/services/note_service.dart';
import 'package:owlistic/services/notebook_service.dart';
import 'package:owlistic/services/task_service.dart';
import 'package:owlistic/services/theme_service.dart';
import 'package:owlistic/services/websocket_service.dart';
import 'package:owlistic/utils/logger.dart';
import 'package:owlistic/viewmodel/home_viewmodel.dart';

class HomeProvider with ChangeNotifier implements HomeViewModel {
  final Logger _logger = Logger('HomeProvider');
  
  // Services
  final AuthService _authService;
  final NoteService _noteService;
  final NotebookService _notebookService;
  final TaskService _taskService;
  final ThemeService _themeService;
  final WebSocketService _webSocketService;
  
  // State variables
  bool _isActive = false;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _errorMessage;
  
  // Data storage
  List<Notebook> _recentNotebooks = [];
  List<Note> _recentNotes = [];
  List<Task> _recentTasks = [];
  ThemeMode _themeMode = ThemeMode.system;
  
  // Constructor with dependency injection
  HomeProvider({
    required AuthService authService,
    required NoteService noteService,
    required NotebookService notebookService,
    required TaskService taskService, 
    required ThemeService themeService,
    required WebSocketService webSocketService,
  }) : _authService = authService,
       _noteService = noteService,
       _notebookService = notebookService,
       _taskService = taskService,
       _themeService = themeService, 
       _webSocketService = webSocketService {
    _initialize();
  }
  
  // Initialize theme mode on startup
  Future<void> _initialize() async {
    try {
      // Initialize theme mode
      _themeMode = await _themeService.getThemeMode();
      _isInitialized = true;
    } catch (e) {
      _logger.error('Error initializing HomeProvider', e);
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
  
  // Implement activate/deactivate from BaseViewModel
  @override
  void activate() {
    _isActive = true;
    _logger.info('HomeProvider activated');
    notifyListeners();
  }
  
  @override
  void deactivate() {
    _isActive = false;
    _logger.info('HomeProvider deactivated');
    notifyListeners();
  }
  
  @override
  void resetState() {
    _recentNotebooks = [];
    _recentNotes = [];
    _recentTasks = [];
    _errorMessage = null;
    notifyListeners();
  }
  
  // Authentication methods
  @override
  Future<User?> get currentUser async {
    try {
      final token = await _authService.getStoredToken();
      if (token != null) {
        return await _authService.getCurrentUser();
      }
    } catch (e) {
      _logger.error('Error getting current user', e);
    }
    return null;
  }
  
  @override
  bool get isLoggedIn => _authService.isLoggedIn;
  
  @override
  Stream<bool> get authStateChanges => _authService.authStateChanges;
  
  @override
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _logger.info('Logging out user');
      await _authService.logout();
      _logger.info('Logout successful');
      
      // Reset state after logout
      resetState();
    } catch (e) {
      _logger.error('Error during logout', e);
      _errorMessage = 'Error logging out: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Notebook functionality
  @override
  List<Notebook> get recentNotebooks => _recentNotebooks;
  
  @override
  bool get hasNotebooks => _recentNotebooks.isNotEmpty;
  
  @override
  Notebook? getNotebook(String notebookId) {
    try {
      return _recentNotebooks.firstWhere(
        (notebook) => notebook.id == notebookId,
      );
    } catch (e) {
      return null;
    }
  }
  
  @override
  Future<void> fetchRecentNotebooks() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Fetch recent notebooks (limit to 5)
      final notebooks = await _notebookService.fetchNotebooks(
        pageSize: 5, 
        page: 1
      );
      
      _recentNotebooks = notebooks;
      _logger.info('Fetched ${notebooks.length} recent notebooks');
    } catch (e) {
      _logger.error('Error fetching recent notebooks', e);
      _errorMessage = 'Error loading notebooks: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  @override
  Future<Notebook?> createNotebook(String name, String description) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final notebook = await _notebookService.createNotebook(name, description);
      
      // Add to recent notebooks if not already there
      if (!_recentNotebooks.any((n) => n.id == notebook.id)) {
        _recentNotebooks = [notebook, ..._recentNotebooks];
        // Keep only most recent 5
        if (_recentNotebooks.length > 5) {
          _recentNotebooks = _recentNotebooks.sublist(0, 5);
        }
      }
      
      _logger.info('Created new notebook: $name');
      return notebook;
    } catch (e) {
      _logger.error('Error creating notebook', e);
      _errorMessage = 'Error creating notebook: ${e.toString()}';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Notes functionality
  @override
  List<Note> get recentNotes => _recentNotes;
  
  @override
  Future<void> fetchRecentNotes() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Fetch recent notes (limit to 5)
      final notes = await _noteService.fetchNotes(
        pageSize: 5,
        page: 1
      );
      
      _recentNotes = notes;
      _logger.info('Fetched ${notes.length} recent notes');
    } catch (e) {
      _logger.error('Error fetching recent notes', e);
      _errorMessage = 'Error loading notes: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  @override
  Future<Note?> createNote(String title, String notebookId) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final note = await _noteService.createNote(notebookId, title);
      
      // Add to recent notes
      _recentNotes = [note, ..._recentNotes];
      // Keep only most recent 5
      if (_recentNotes.length > 5) {
        _recentNotes = _recentNotes.sublist(0, 5);
      }
      
      _logger.info('Created new note: $title');
      return note;
    } catch (e) {
      _logger.error('Error creating note', e);
      _errorMessage = 'Error creating note: ${e.toString()}';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Tasks functionality
  @override
  List<Task> get recentTasks => _recentTasks;
  
  @override
  Future<void> fetchRecentTasks() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Fetch recent tasks (limit to 5)
      final tasks = await _taskService.fetchTasks(
        queryParams: {'page': '1', 'page_size': '5'}
      );
      
      _recentTasks = tasks;
      _logger.info('Fetched ${tasks.length} recent tasks');
    } catch (e) {
      _logger.error('Error fetching recent tasks', e);
      _errorMessage = 'Error loading tasks: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  @override
  Future<Task?> createTask(String title, String category) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // First note ID or default
      final String noteId = _recentNotes.isNotEmpty 
          ? _recentNotes.first.id 
          : '00000000-0000-0000-0000-000000000000';
      
      final task = await _taskService.createTask(title, noteId);
      
      // Add to recent tasks
      _recentTasks = [task, ..._recentTasks];
      // Keep only most recent 5
      if (_recentTasks.length > 5) {
        _recentTasks = _recentTasks.sublist(0, 5);
      }
      
      _logger.info('Created new task: $title');
      return task;
    } catch (e) {
      _logger.error('Error creating task', e);
      _errorMessage = 'Error creating task: ${e.toString()}';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  @override
  Future<void> toggleTaskCompletion(String taskId, bool isCompleted) async {
    try {
      // Find the task in our list
      final index = _recentTasks.indexWhere((t) => t.id == taskId);
      if (index == -1) {
        _logger.warning('Task $taskId not found in recent tasks');
        return;
      }
      
      // Update UI immediately for responsiveness
      final updatedTask = _recentTasks[index].copyWith(isCompleted: isCompleted);
      _recentTasks[index] = updatedTask;
      notifyListeners();
      
      // Perform API update
      await _taskService.updateTask(taskId, isCompleted: isCompleted);
      _logger.info('Toggled task $taskId completion to $isCompleted');
    } catch (e) {
      _logger.error('Error toggling task completion', e);
      _errorMessage = 'Error updating task: ${e.toString()}';
      notifyListeners();
      
      // Revert the change if the API call failed
      await fetchRecentTasks();
    }
  }
  
  // WebSocket connection
  @override
  Future<void> ensureConnected() async {
    try {
      if (!_webSocketService.isConnected) {
        await _webSocketService.connect();
        _logger.info('WebSocket connection established');
      }
    } catch (e) {
      _logger.error('Error connecting to WebSocket', e);
      _errorMessage = 'Error connecting to server: ${e.toString()}';
      notifyListeners();
    }
  }
}
