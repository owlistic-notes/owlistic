import 'package:owlistic/models/note.dart';
import 'package:owlistic/models/notebook.dart';
import 'package:owlistic/models/task.dart';
import 'package:owlistic/models/user.dart';
import 'base_viewmodel.dart';

/// Interface for home screen functionality.
/// This represents a consolidated API for the home screen to interact with all services.
abstract class HomeViewModel extends BaseViewModel {
  // User information
  Future<User?> get currentUser;
  bool get isLoggedIn;
  Stream<bool> get authStateChanges;
  
  // Authentication methods
  Future<void> logout();
  
  // Notebook functionality
  List<Notebook> get recentNotebooks;
  Future<void> fetchRecentNotebooks();
  Future<Notebook?> createNotebook(String name, String description);
  bool get hasNotebooks;
  Notebook? getNotebook(String notebookId);

  // Notes functionality
  List<Note> get recentNotes;
  Future<void> fetchRecentNotes();
  Future<Note?> createNote(String title, String notebookId);

  // Tasks functionality
  List<Task> get recentTasks;
  Future<void> fetchRecentTasks();
  Future<Task?> createTask(String title, String category);
  Future<void> toggleTaskCompletion(String taskId, bool isCompleted);

  // WebSocket connection
  Future<void> ensureConnected();
}
