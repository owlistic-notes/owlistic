import 'dart:async';
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/task_service.dart';
import '../services/auth_service.dart';
import '../services/base_service.dart';
import 'websocket_provider.dart';
import '../utils/logger.dart';

class TasksProvider with ChangeNotifier {
  // Change to Map to prevent duplicates and enable O(1) lookups
  final Map<String, Task> _tasksMap = {};
  bool _isLoading = false;
  WebSocketProvider? _webSocketProvider;
  bool _initialized = false;
  bool _isActive = false; // Add flag for active state
  
  // Services
  final TaskService _taskService;
  final AuthService _authService;

  // Logger for debugging and tracking events
  final _logger = Logger('TaskProvider');

  // Constructor with dependency injection
  TasksProvider({TaskService? taskService, AuthService? authService})
    : _taskService = taskService ?? ServiceLocator.get<TaskService>(),
      _authService = authService ?? ServiceLocator.get<AuthService>();

  // Update getters to use the map
  List<Task> get tasks => _tasksMap.values.toList();
  bool get isLoading => _isLoading;
  List<Task> get recentTasks => _tasksMap.values.take(3).toList();
  
  // Add activation/deactivation pattern
  void activate() {
    _isActive = true;
    _logger.info('TasksProvider activated');
    fetchTasks(); // Load tasks on activation
  }

  void deactivate() {
    _isActive = false;
    _logger.info('TasksProvider deactivated');
  }

  // Called by ProxyProvider in main.dart
  void initialize(WebSocketProvider webSocketProvider) {
    if (_initialized) return;
    _initialized = true;

    _webSocketProvider = webSocketProvider;
    _registerEventHandlers();

    _logger.info('TasksProvider registered event handlers');
  }

  void setWebSocketProvider(WebSocketProvider provider) {
    if (_webSocketProvider == provider) return;

    _webSocketProvider = provider;

    // Register for relevant events
    _registerEventHandlers();

    _logger.info('TasksProvider: WebSocket event listeners registered');
  }

  void _registerEventHandlers() {
    // Register handlers for all standardized resource.action events
    _webSocketProvider?.addEventListener(
        'event', 'task.updated', _handleTaskUpdate);
    _webSocketProvider?.addEventListener(
        'event', 'task.created', _handleTaskCreate);
    _webSocketProvider?.addEventListener(
        'event', 'task.deleted', _handleTaskDelete);
  }

  void _handleTaskUpdate(Map<String, dynamic> message) {
    if (!_isActive) return; // Only process events when active
    
    final payload = message['payload'];
    if (payload == null || payload['data'] == null) return;

    final data = payload['data'];
    final String taskId = _extractTaskId(data);

    if (taskId.isNotEmpty) {
      _fetchSingleTask(taskId);
    }
  }

  void _handleTaskCreate(Map<String, dynamic> payload) {
    if (!_isActive) return; // Only process events when active
    
    final data = payload['data'];
    final String taskId = _extractTaskId(data);
    final String noteId =
        data['note_id'] != null ? data['note_id'].toString() : '';

    if (taskId.isNotEmpty) {
      // Only fetch if we have tasks for this note already or if we're showing all tasks
      if (noteId.isEmpty ||
          _tasksMap.values.any((task) => task.noteId == noteId)) {
        _fetchSingleTask(taskId);
      }
    }
  }

  void _handleTaskDelete(Map<String, dynamic> payload) {
    if (!_isActive) return; // Only process events when active
    
    final data = payload['data'];
    final String taskId = _extractTaskId(data);

    if (taskId.isNotEmpty) {
      // Remove task from local state if it exists
      _tasksMap.remove(taskId);
      notifyListeners();
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
    print('Fetching single task: $taskId');
    try {
      // Fetch the task from the service
      final task = await _taskService.getTask(taskId);

      // Update the task in our map
      _tasksMap[taskId] = task;

      // Subscribe to this task
      _webSocketProvider?.subscribe('task', id: task.id);

      notifyListeners();
      print('Updated/added task: $taskId');
    } catch (error) {
      print('Error fetching task: $error');
    }
  }

  Future<void> fetchTasks() async {
    if (!_isActive) return; // Don't fetch if not active
    
    _isLoading = true;
    notifyListeners();

    try {
      final tasksList = await _taskService.fetchTasks();

      // Convert list to map
      _tasksMap.clear();
      for (final task in tasksList) {
        _tasksMap[task.id] = task;
      }

      // Subscribe to all tasks
      for (var task in tasksList) {
        _webSocketProvider?.subscribe('task', id: task.id);
      }

      print('Fetched ${_tasksMap.length} tasks');
    } catch (error) {
      print('Error fetching tasks: $error');
      _tasksMap.clear(); // Reset tasks on error
    }

    _isLoading = false;
    notifyListeners();
  }

  // Create task - no optimistic updates
  Future<void> createTask(String title, String noteId, {String? blockId}) async {
    try {
      // Get user ID from auth service directly
      final currentUser = await _authService.getUserProfile();
      final userId = currentUser?.id ?? '';
      
      // Create task on server
      final task = await _taskService.createTask(title, noteId, userId, blockId: blockId);
      
      // Subscribe to this task
      _webSocketProvider?.subscribe('task', id: task.id);
      
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
    // Unregister event handlers
    if (_webSocketProvider != null) {
      _webSocketProvider?.removeEventListener('event', 'task_updated');
      _webSocketProvider?.removeEventListener('event', 'task_created');
      _webSocketProvider?.removeEventListener('event', 'task_deleted');
    }
    super.dispose();
  }
}
