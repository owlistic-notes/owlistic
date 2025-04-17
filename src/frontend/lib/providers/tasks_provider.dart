import 'dart:async';
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'websocket_provider.dart';

class TasksProvider with ChangeNotifier {
  // Change to Map to prevent duplicates and enable O(1) lookups
  final Map<String, Task> _tasksMap = {};
  bool _isLoading = false;
  final WebSocketService _webSocketService = WebSocketService();
  WebSocketProvider? _webSocketProvider;
  bool _initialized = false;

  // Update getters to use the map
  List<Task> get tasks => _tasksMap.values.toList();
  bool get isLoading => _isLoading;
  List<Task> get recentTasks => _tasksMap.values.take(3).toList();

  TasksProvider() {
    // Initialize WebSocket connection
    _webSocketService.connect();
    print('TasksProvider initialized');
  }
  
  // Called by ProxyProvider in main.dart
  void initialize(WebSocketProvider webSocketProvider) {
    if (_initialized) return;
    _initialized = true;
    
    _webSocketProvider = webSocketProvider;
    _registerEventHandlers();
    
    print('TasksProvider registered event handlers');
  }
  
  void setWebSocketProvider(WebSocketProvider provider) {
    if (_webSocketProvider == provider) return;
    
    _webSocketProvider = provider;
    
    // Register for relevant events
    _registerEventHandlers();
    
    print('TasksProvider: WebSocket event listeners registered');
  }
  
  void _registerEventHandlers() {
    // Register handlers for all standardized resource.action events
    _webSocketProvider?.addEventListener('event', 'task.updated', _handleTaskUpdate);
    _webSocketProvider?.addEventListener('event', 'task.created', _handleTaskCreate);
    _webSocketProvider?.addEventListener('event', 'task.deleted', _handleTaskDelete);
  }
  
  void _handleTaskUpdate(Map<String, dynamic> message) {
    final payload = message['payload'];
    if (payload == null || payload['data'] == null) return;
    
    final data = payload['data'];
    final String taskId = _extractTaskId(data);
    
    if (taskId.isNotEmpty) {
      _fetchSingleTask(taskId);
    }
  }
  
  void _handleTaskCreate(Map<String, dynamic> payload) {
    final data = payload['data'];
    final String taskId = _extractTaskId(data);
    final String noteId = data['note_id'] != null ? data['note_id'].toString() : '';
    
    if (taskId.isNotEmpty) {
      // Only fetch if we have tasks for this note already or if we're showing all tasks
      if (noteId.isEmpty || _tasksMap.values.any((task) => task.noteId == noteId)) {
        _fetchSingleTask(taskId);
      }
    }
  }
  
  void _handleTaskDelete(Map<String, dynamic> payload) {
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
      // Since there's no getTask method in ApiService, we'll fetch all tasks and filter
      // In a real app, you would add a getTask method to ApiService
      final task = await ApiService.getTask(taskId);
      
      // Update the task in our map
      _tasksMap[taskId] = task;
      
      // Subscribe to this task
      _webSocketService.subscribe('task', id: task.id);
      
      print('Updated/added task: $taskId');
      notifyListeners();
    } catch (error) {
      print('Error fetching task: $error');
    }
  }

  Future<void> fetchTasks() async {
    _isLoading = true;
    notifyListeners();

    try {
      final tasksList = await ApiService.fetchTasks();
      
      // Convert list to map
      _tasksMap.clear();
      for (final task in tasksList) {
        _tasksMap[task.id] = task;
      }
      
      // Subscribe to all tasks
      for (var task in tasksList) {
        _webSocketService.subscribe('task', id: task.id);
      }
      
      print('Fetched ${_tasksMap.length} tasks');
    } catch (error) {
      print('Error fetching tasks: $error');
      _tasksMap.clear(); // Reset tasks on error
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> createTask(String title, String noteId, {String? blockId}) async {
    try {
      final task = await ApiService.createTask(title, noteId, blockId: blockId);
      _tasksMap[task.id] = task;
      
      // Subscribe to this task
      _webSocketService.subscribe('task', id: task.id);
      
      notifyListeners();
    } catch (error) {
      print('Error creating task: $error');
      rethrow;
    }
  }

  Future<void> deleteTask(String id) async {
    try {
      await ApiService.deleteTask(id);
      _tasksMap.remove(id);
      
      // Unsubscribe from this task
      _webSocketService.unsubscribe('task', id: id);
      
      notifyListeners();
    } catch (error) {
      print('Error deleting task: $error');
      rethrow;
    }
  }

  Future<void> updateTaskTitle(String id, String title) async {
    try {
      final updatedTask = await ApiService.updateTask(id, title: title);
      _tasksMap[id] = updatedTask;
      notifyListeners();
    } catch (error) {
      print('Error updating task: $error');
      rethrow;
    }
  }

  Future<void> toggleTaskCompletion(String id, bool isCompleted) async {
    try {
      final updatedTask = await ApiService.updateTask(id, isCompleted: isCompleted);
      _tasksMap[id] = updatedTask;
      notifyListeners();
    } catch (error) {
      print('Error updating task: $error');
      rethrow;
    }
  }

  // Method to fetch a task from a WebSocket event
  Future<void> fetchTaskFromEvent(String taskId) async {
    try {
      // Only fetch if we don't already have this task or if it's being updated
      final task = await ApiService.getTask(taskId);
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
        final task = await ApiService.getTask(taskId);
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
