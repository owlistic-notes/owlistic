import 'dart:async';
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/task_service.dart';
import '../services/auth_service.dart';
import '../services/base_service.dart';
import '../services/websocket_service.dart';
import '../utils/logger.dart';
import '../utils/websocket_message_parser.dart';
import '../services/app_state_service.dart';

class TasksProvider with ChangeNotifier {
  // Change to Map to prevent duplicates and enable O(1) lookups
  final Map<String, Task> _tasksMap = {};
  bool _isLoading = false;
  bool _isActive = false; // Add flag for active state
  bool _initialized = false;
  
  // Services
  final TaskService _taskService;
  final AuthService _authService;
  final WebSocketService _webSocketService = WebSocketService();

  // Add subscription for app state changes
  StreamSubscription? _resetSubscription;
  StreamSubscription? _connectionSubscription;
  final AppStateService _appStateService = AppStateService();

  // Logger for debugging and tracking events
  final _logger = Logger('TaskProvider');

  // Constructor with dependency injection
  TasksProvider({TaskService? taskService, AuthService? authService})
    : _taskService = taskService ?? ServiceLocator.get<TaskService>(),
      _authService = authService ?? ServiceLocator.get<AuthService>() {
    // Listen for app reset events
    _resetSubscription = _appStateService.onResetState.listen((_) {
      resetState();
    });
    
    // Initialize event handlers if not already initialized
    if (!_initialized) {
      _initializeEventListeners();
      _initialized = true;
    }
    
    // Listen for connection state changes
    _connectionSubscription = _webSocketService.connectionStateStream.listen((connected) {
      if (connected && _isActive) {
        // Resubscribe to events when connection is established
        _subscribeToEvents();
      }
    });
  }

  // Initialize WebSocket event listeners
  void _initializeEventListeners() {
    _webSocketService.addEventListener('event', 'task.updated', _handleTaskUpdate);
    _webSocketService.addEventListener('event', 'task.created', _handleTaskCreate);
    _webSocketService.addEventListener('event', 'task.deleted', _handleTaskDelete);
    
    _logger.info('TasksProvider registered event handlers');
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

  // Update getters to use the map
  List<Task> get tasks => _tasksMap.values.toList();
  bool get isLoading => _isLoading;
  List<Task> get recentTasks => _tasksMap.values.take(3).toList();
  
  // Reset state on logout
  void resetState() {
    _logger.info('Resetting TasksProvider state');
    _tasksMap.clear();
    _isActive = false;
    notifyListeners();
  }
  
  // Add activation/deactivation pattern
  void activate() {
    _isActive = true;
    _logger.info('TasksProvider activated');
    
    // Subscribe to events when activated
    if (_webSocketService.isConnected) {
      _subscribeToEvents();
    }
    
    fetchTasks(); // Load tasks on activation
  }

  void deactivate() {
    _isActive = false;
    _logger.info('TasksProvider deactivated');
  }

  void _handleTaskUpdate(Map<String, dynamic> message) {
    if (!_isActive) return; // Only process events when active
    
    try {
      // Use the standardized parser
      final parsedMessage = WebSocketMessage.fromJson(message);
      final String? taskId = WebSocketModelExtractor.extractBlockId(parsedMessage); // Using block extractor as tasks don't have a specific extractor
      
      if (taskId != null && taskId.isNotEmpty) {
        _fetchSingleTask(taskId);
      } else {
        _logger.warning('Could not extract task_id from message');
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
      final payload = parsedMessage.payload;
      final data = payload['data'];
      
      String taskId = '';
      String noteId = '';
      
      // Extract IDs - tasks don't have a specific extractor yet
      if (data != null && data is Map) {
        taskId = data['id']?.toString() ?? data['task_id']?.toString() ?? '';
        noteId = data['note_id']?.toString() ?? '';
      }
      
      if (taskId.isNotEmpty) {
        // Only fetch if we have tasks for this note already or if we're showing all tasks
        if (noteId.isEmpty || _tasksMap.values.any((task) => task.noteId == noteId)) {
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
      final payload = parsedMessage.payload;
      final data = payload['data'];
      
      String taskId = '';
      
      // Extract task ID - tasks don't have a specific extractor yet
      if (data != null && data is Map) {
        taskId = data['id']?.toString() ?? data['task_id']?.toString() ?? '';
      }
      
      if (taskId.isNotEmpty) {
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

  String _extractTaskId(dynamic data) {
    if (data == null) return '';

    String taskId = '';
    if (data['task_id'] != null) {
      taskId = data['task_id'].toString();
    } else if (data['id'] != null) {
      taskId = data['id'].toString();
    }

    return taskId;
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
  Future<void> fetchTasks({String? completed, String? noteId}) async {
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
      final tasksList = await _taskService.fetchTasks(
        completed: completed,
        noteId: noteId,
      );

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

  // Create task - no optimistic updates
  Future<void> createTask(String title, String noteId, {String? blockId}) async {
    try {
      // Create task on server
      final task = await _taskService.createTask(title, noteId, blockId: blockId);
      
      // Subscribe to this task
      _webSocketService.subscribe('task', id: task.id);
      
      _logger.info('Created task: $title, waiting for event');
    } catch (error) {
      _logger.error('Error creating task: $error');
      rethrow;
    }
  }

  Future<void> deleteTask(String id) async {
    try {
      // Delete task on server
      await _taskService.deleteTask(id);
      
      _logger.info('Deleted task: $id, waiting for event');
    } catch (error) {
      _logger.error('Error deleting task: $error');
      rethrow;
    }
  }

  Future<void> updateTaskTitle(String id, String title) async {
    try {
      // Update task on server
      await _taskService.updateTask(id, title: title);
      
      _logger.info('Updated task title: $title, waiting for event');
    } catch (error) {
      _logger.error('Error updating task title: $error');
      rethrow;
    }
  }

  Future<void> toggleTaskCompletion(String id, bool isCompleted) async {
    try {
      // Update task on server
      await _taskService.updateTask(id, isCompleted: isCompleted);
      
      _logger.info('Toggled task completion: $isCompleted, waiting for event');
    } catch (error) {
      _logger.error('Error toggling task completion: $error');
      rethrow;
    }
  }

  // Method to fetch a task from a WebSocket event
  Future<void> fetchTaskFromEvent(String taskId) async {
    try {
      // Only fetch if we don't already have this task or if it's being updated
      final task = await _taskService.getTask(taskId);
      _tasksMap[taskId] = task;
      notifyListeners();
    } catch (error) {
      print('Error fetching task from event: $error');
    }
  }

  // Method to add a task from a WebSocket event
  Future<void> addTaskFromEvent(String taskId) async {
    try {
      // Only fetch if we don't already have this task
      if (!_tasksMap.containsKey(taskId)) {
        final task = await _taskService.getTask(taskId);
        _tasksMap[taskId] = task;
        notifyListeners();
      }
    } catch (error) {
      print('Error adding task from event: $error');
    }
  }

  // Method to handle task deletion events
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
