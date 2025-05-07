import '../models/task.dart';
import '../models/note.dart';
import 'base_viewmodel.dart';

/// Interface for task management functionality
abstract class TasksViewModel extends BaseViewModel {
  /// All tasks
  List<Task> get tasks;
  
  /// Recent tasks (limited set)
  List<Task> get recentTasks;
  
  /// Available notes for task creation
  List<Note> get availableNotes;
  
  /// Fetch tasks with filtering
  Future<void> fetchTasks({String? completed, String? noteId});
  
  /// Load available notes for task creation
  Future<void> loadAvailableNotes();
  
  /// Create a new task
  Future<void> createTask(String title, String noteId, {String? blockId});
  
  /// Delete a task
  Future<void> deleteTask(String id);
  
  /// Update a task's title
  Future<void> updateTaskTitle(String id, String title);
  
  /// Toggle completion status
  Future<void> toggleTaskCompletion(String id, bool isCompleted);
  
  /// Fetch a task from a WebSocket event
  Future<void> fetchTaskFromEvent(String taskId);
  
  /// Add a task from a WebSocket event
  Future<void> addTaskFromEvent(String taskId);
  
  /// Handle task deletion events
  void handleTaskDeleted(String taskId);
}
