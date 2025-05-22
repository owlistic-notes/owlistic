import 'dart:async';
import 'package:flutter/material.dart';
import 'package:owlistic/models/note.dart';
import 'package:owlistic/models/task.dart';
import 'package:owlistic/services/note_service.dart';
import 'package:owlistic/services/task_service.dart';
import 'package:owlistic/services/auth_service.dart';
import 'package:owlistic/services/websocket_service.dart';
import 'package:owlistic/utils/logger.dart';
import 'package:owlistic/utils/websocket_message_parser.dart';
import 'package:owlistic/services/app_state_service.dart';
import 'package:owlistic/viewmodel/tasks_viewmodel.dart';

class TasksProvider with ChangeNotifier implements TasksViewModel {
  // Change to Map to prevent duplicates and enable O(1) lookups
  final Map<String, Task> _tasksMap = {};
  final Map<String, Note> _notesMap = {}; // Add notes map
  bool _isLoading = false;
  bool _isActive = false; // Add flag for active state
  bool _isInitialized = false;  // Standardize the variable name
  String? _errorMessage;
  
  // Services
  final TaskService _taskService;
  final AuthService _authService;
  final WebSocketService _webSocketService;
  final NoteService _noteService; // Add note service

  // Add subscription for app state changes
  StreamSubscription? _resetSubscription;
  StreamSubscription? _connectionSubscription;
  final AppStateService _appStateService = AppStateService();

  // Logger for debugging and tracking events
  final _logger = Logger('TaskProvider');

  // Constructor with dependency injection - add NoteService parameter
  TasksProvider({
    required TaskService taskService, 
    required AuthService authService,
    required WebSocketService webSocketService,
    required NoteService noteService
  }) : _taskService = taskService,
       _authService = authService,
       _webSocketService = webSocketService,
       _noteService = noteService {
    // Listen for app reset events
    _resetSubscription = _appStateService.onResetState.listen((_) {
      resetState();
    });
    
    // Initialize event handlers
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
    _logger.info('TasksProvider initialized');
  }

  // Initialize WebSocket event listeners
  void _initializeEventListeners() {
    _webSocketService.addEventListener('event', 'task.created', _handleTaskCreate);
    _webSocketService.addEventListener('event', 'task.updated', _handleTaskUpdate);
    _webSocketService.addEventListener('event', 'task.deleted', _handleTaskDelete);
  }

  
  // Subscribe to events
  void _subscribeToEvents() {
    _webSocketService.subscribeToEvent('task.updated');
    _webSocketService.subscribeToEvent('task.created');
    _webSocketService.subscribeToEvent('task.deleted');
    
    // Also subscribe to tasks for any active tasks
    for (final task in _tasksMap.values) {
      _webSocketService.subscribe('task', id: task.id);
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
  
  // TasksPresenter implementation
  @override
  List<Task> get tasks => _tasksMap.values.toList();
  
  @override
  List<Task> get recentTasks => _tasksMap.values.take(3).toList();
  
  @override
  List<Note> get availableNotes => _notesMap.values.toList();

  // Reset state on logout
  @override
  void resetState() {
    _logger.info('Resetting TasksProvider state');
    _tasksMap.clear();
    _notesMap.clear();
    _isActive = false;
    notifyListeners();
  }
  
  // Add activation/deactivation pattern
  @override
  void activate() {
    _isActive = true;
    _logger.info('TasksProvider activated');
    
    // Subscribe to events when activated
    if (_webSocketService.isConnected) {
      _subscribeToEvents();
    }
    
    fetchTasks(); // Load tasks on activation
    loadAvailableNotes(); // Load notes on activation
  }

  @override
  void deactivate() {
    _isActive = false;
    _logger.info('TasksProvider deactivated');
  }

  void _handleTaskUpdate(Map<String, dynamic> message) {
    if (!_isActive) return; // Only process events when active
    
    try {
      // Use the standardized parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? taskId = WebSocketModelExtractor.extractTaskId(parsedMessage);
      
      if (taskId != null && taskId.isNotEmpty) {
        // Always fetch the task when it's updated
        _fetchSingleTask(taskId);
        _logger.debug('Processing task update for task ID: $taskId');
      } else {
        _logger.warning('Could not extract task_id from message: ${message.toString().substring(0, 100)}...');
      }
    } catch (e) {
      _logger.error('Error handling task update: $e');
    }
  }

  void _handleTaskCreate(Map<String, dynamic> message) {
    if (!_isActive) return; // Only process events when active
    
    try {
      // Use the standardized parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? taskId = WebSocketModelExtractor.extractTaskId(parsedMessage);
      final String? noteId = WebSocketModelExtractor.extractNoteId(parsedMessage);
      
      if (taskId != null && taskId.isNotEmpty) {
        // Only fetch if we have tasks for this note already or if we're showing all tasks
        if ((noteId != null && noteId.isNotEmpty) || _tasksMap.values.any((task) => task.noteId == noteId)) {
          _fetchSingleTask(taskId);
        }
      } else {
        _logger.warning('Could not extract task_id from message');
      }
    } catch (e) {
      _logger.error('Error handling task create: $e');
    }
  }

  void _handleTaskDelete(Map<String, dynamic> message) {
    if (!_isActive) return; // Only process events when active
    
    try {
      // Use the standardized parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? taskId = WebSocketModelExtractor.extractTaskId(parsedMessage);
      
      if (taskId != null && taskId.isNotEmpty) {
        // Remove task from local state if it exists
        _tasksMap.remove(taskId);
        notifyListeners();
      } else {
        _logger.warning('Could not extract task_id from message');
      }
    } catch (e) {
      _logger.error('Error handling task delete: $e');
    }
  }

  Future<void> _fetchSingleTask(String taskId) async {
    _logger.debug('Fetching single task: $taskId');
    
    try {
      // Fetch the task from the service
      final task = await _taskService.getTask(taskId);

      // Update the task in our map
      _tasksMap[taskId] = task;

      // Subscribe to this task
      _webSocketService.subscribe('task', id: task.id);

      notifyListeners();
      _logger.debug('Updated/added task: $taskId');
    } catch (error) {
      _logger.error('Error fetching task: $error');
    }
  }

  // Fetch tasks with proper user filtering
  @override
  Future<void> fetchTasks({String? noteId}) async {
    if (!_isActive) return; // Don't fetch if not active
    
    // Get current user ID for filtering
    final currentUser = await _authService.getUserProfile();
    if (currentUser == null) {
      _logger.warning('Cannot fetch tasks: No authenticated user');
      return;
    }
    
    _isLoading = true;
    notifyListeners();

    try {
      final tasksList = await _taskService.fetchTasks(noteId: noteId);

      // Convert list to map
      _tasksMap.clear();
      for (final task in tasksList) {
        _tasksMap[task.id] = task;
      }

      // Subscribe to all tasks
      for (var task in tasksList) {
        _webSocketService.subscribe('task', id: task.id);
      }

      _logger.debug('Fetched ${_tasksMap.length} tasks');
    } catch (error) {
      _logger.error('Error fetching tasks: $error');
      _tasksMap.clear(); // Reset tasks on error
    }

    _isLoading = false;
    notifyListeners();
  }

  @override
  Future<void> loadAvailableNotes() async {
    if (!_isActive) return; // Don't fetch if not active
    
    try {
      final notes = await _noteService.getNotes();
      
      _notesMap.clear();
      for (final note in notes) {
        _notesMap[note.id] = note;
      }
      
      notifyListeners();
      _logger.debug('Loaded ${_notesMap.length} notes for task creation');
    } catch (error) {
      _logger.error('Error loading available notes: $error');
    }
  }

  // Create task - updated to include optimistic update
  @override
  Future<void> createTask(String title, String noteId) async {
    try {
      // Create task on server
      final task = await _taskService.createTask(title, noteId);
      
      // Optimistic update - add task to local state immediately
      _tasksMap[task.id] = task;
      notifyListeners();
      
      // Subscribe to this task
      _webSocketService.subscribe('task', id: task.id);
      
      _logger.info('Created task: $title with noteId: $noteId');
    } catch (error) {
      _logger.error('Error creating task: $error');
      notifyListeners(); // Notify even on error to update UI
      rethrow;
    }
  }

  @override
  Future<void> deleteTask(String id) async {
    // Save current task for potential restore
    final Task? originalTask = _tasksMap[id];
    
    // Optimistic update - remove from UI immediately
    _tasksMap.remove(id);
    notifyListeners();
    
    try {
      // Delete task on server
      await _taskService.deleteTask(id);
      _logger.info('Deleted task: $id');
    } catch (error) {
      // Restore task on error
      if (originalTask != null) {
        _tasksMap[id] = originalTask;
        notifyListeners();
      }
      _logger.error('Error deleting task: $error');
      rethrow;
    }
  }

  @override
  Future<void> updateTaskTitle(String id, String title) async {
    // Save original for potential restore
    final Task? originalTask = _tasksMap[id];
    if (originalTask == null) return;
    
    // Optimistic update
    final updatedTask = originalTask.copyWith(
      title: title,
      updatedAt: DateTime.now(),
    );
    
    _tasksMap[id] = updatedTask;
    notifyListeners();
    
    try {
      // Update task on server
      await _taskService.updateTask(id, title: title);
      _logger.info('Updated task title: $title');
    } catch (error) {
      // Restore on error
      _tasksMap[id] = originalTask;
      notifyListeners();
      _logger.error('Error updating task title: $error');
      rethrow;
    }
  }

  @override
  Future<void> toggleTaskCompletion(String id, bool isCompleted) async {
    // Save original for potential restore
    final Task? originalTask = _tasksMap[id];
    if (originalTask == null) return;
    
    // Optimistic update
    final updatedTask = originalTask.copyWith(
      isCompleted: isCompleted,
      updatedAt: DateTime.now(),
    );
    
    _tasksMap[id] = updatedTask;
    notifyListeners();
    
    try {
      // Update task on server
      await _taskService.updateTask(id, isCompleted: isCompleted);
      _logger.info('Toggled task completion: $isCompleted');
    } catch (error) {
      // Restore on error
      _tasksMap[id] = originalTask;
      notifyListeners();
      _logger.error('Error toggling task completion: $error');
      rethrow;
    }
  }

  // Method to fetch a task from a WebSocket event
  @override
  Future<void> fetchTaskFromEvent(String taskId) async {
    try {
      // Only fetch if we don't already have this task or if it's being updated
      final task = await _taskService.getTask(taskId);
      _tasksMap[taskId] = task;
      notifyListeners();
    } catch (error) {
      _logger.error('Error fetching task from event: $error');
    }
  }

  // Method to add a task from a WebSocket event
  @override
  Future<void> addTaskFromEvent(String taskId) async {
    try {
      // Only fetch if we don't already have this task
      if (!_tasksMap.containsKey(taskId)) {
        final task = await _taskService.getTask(taskId);
        _tasksMap[taskId] = task;
        notifyListeners();
      }
    } catch (error) {
      _logger.error('Error adding task from event: $error');
    }
  }

  // Method to handle task deletion events
  @override
  void handleTaskDeleted(String taskId) {
    if (_tasksMap.containsKey(taskId)) {
      _tasksMap.remove(taskId);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _resetSubscription?.cancel();
    _connectionSubscription?.cancel();
    
    // Remove event listeners
    _webSocketService.removeEventListener('event', 'task.updated');
    _webSocketService.removeEventListener('event', 'task.created');
    _webSocketService.removeEventListener('event', 'task.deleted');
    
    super.dispose();
  }
}
