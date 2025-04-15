import 'dart:async';
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'websocket_provider.dart';

class TasksProvider with ChangeNotifier {
  List<Task> _tasks = [];
  bool _isLoading = false;
  final WebSocketService _webSocketService = WebSocketService();
  WebSocketProvider? _webSocketProvider;
  bool _initialized = false;

  List<Task> get tasks => [..._tasks];
  bool get isLoading => _isLoading;
  List<Task> get recentTasks => _tasks.take(3).toList();

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
    // Register handlers for all relevant event types
    _webSocketProvider?.addEventListener('event', 'task_updated', _handleTaskUpdate);
    _webSocketProvider?.addEventListener('event', 'task_created', _handleTaskCreate);
    _webSocketProvider?.addEventListener('event', 'task_deleted', _handleTaskDelete);
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
      if (noteId.isEmpty || _tasks.any((task) => task.noteId == noteId)) {
        _fetchSingleTask(taskId);
      }
    }
  }
  
  void _handleTaskDelete(Map<String, dynamic> payload) {
    final data = payload['data'];
    final String taskId = _extractTaskId(data);
    
    if (taskId.isNotEmpty) {
      // Remove task from local state if it exists
      _tasks.removeWhere((task) => task.id == taskId);
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
      final tasks = await ApiService.fetchTasks();
      final task = tasks.firstWhere(
        (t) => t.id == taskId,
        orElse: () => throw Exception('Task not found'),
      );
      
      // Check if task exists in our list
      final index = _tasks.indexWhere((t) => t.id == taskId);
      if (index != -1) {
        _tasks[index] = task;
      } else {
        _tasks.add(task);
        // Subscribe to this task
        _webSocketService.subscribe('task', id: task.id);
      }
      
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
      _tasks = await ApiService.fetchTasks();
      
      // Subscribe to all tasks
      for (var task in _tasks) {
        _webSocketService.subscribe('task', id: task.id);
      }
      
      print('Fetched ${_tasks.length} tasks');
    } catch (error) {
      print('Error fetching tasks: $error');
      _tasks = []; // Reset tasks on error
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> createTask(String title, String noteId, {String? blockId}) async {
    try {
      final task = await ApiService.createTask(title, noteId, blockId: blockId);
      _tasks.add(task);
      
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
      _tasks.removeWhere((task) => task.id == id);
      
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
      final index = _tasks.indexWhere((task) => task.id == id);
      if (index != -1) {
        _tasks[index] = updatedTask;
        notifyListeners();
      }
    } catch (error) {
      print('Error updating task: $error');
      rethrow;
    }
  }

  Future<void> toggleTaskCompletion(String id, bool isCompleted) async {
    try {
      final updatedTask = await ApiService.updateTask(id, isCompleted: isCompleted);
      final index = _tasks.indexWhere((task) => task.id == id);
      if (index != -1) {
        _tasks[index] = updatedTask;
        notifyListeners();
      }
    } catch (error) {
      print('Error updating task: $error');
      rethrow;
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
