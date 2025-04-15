import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/api_service.dart';

class TasksProvider with ChangeNotifier {
  List<Task> _tasks = [];
  bool _isLoading = false;

  List<Task> get tasks => [..._tasks];
  bool get isLoading => _isLoading;
  List<Task> get recentTasks => _tasks.take(3).toList();

  Future<void> fetchTasks() async {
    _isLoading = true;
    notifyListeners();

    try {
      _tasks = await ApiService.fetchTasks();
      print('Fetched ${_tasks.length} tasks');
    } catch (error) {
      print('Error fetching tasks: $error');
      _tasks = []; // Reset tasks on error
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> createTask(String title) async {
    try {
      final task = await ApiService.createTask(title);
      _tasks.add(task);
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
}
