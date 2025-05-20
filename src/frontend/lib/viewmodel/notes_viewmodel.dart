import 'package:owlistic/models/note.dart';
import 'package:owlistic/models/notebook.dart';
import 'base_viewmodel.dart';

abstract class NotesViewModel extends BaseViewModel {
  // Getters
  List<Note> get notes;
  List<Notebook> get notebooks;
  bool get isEmpty;
  int get updateCount;
  List<Note> get recentNotes;
  
  // Fetch operations
  Future<List<Note>> fetchNotes({
    String? notebookId, 
    int page = 1, 
    int pageSize = 20,
    List<String>? excludeIds
  });
  
  Future<Note?> fetchNoteById(String id);
  
  // Note grouping/filtering
  List<Note> getNotesByNotebookId(String notebookId);
  
  // CRUD operations with proper typing
  Future<Note> createNote(String title, String? notebookId);
  Future<void> deleteNote(String id);
  Future<Note> updateNote(String id, String title, {String? notebookId});
  
  // Note activation methods for real-time editing
  void activateNote(String noteId);
  void deactivateNote(String noteId);
  
  // Event handling method for consistency
  void handleNoteDeleted(String id);

  /// Move a note from one notebook to another
  Future<void> moveNote(String noteId, String newNotebookId);

  /// Get a notebook by ID from cache
  Future<Note?> addNoteToNotebook(String notebookId, String title);

  /// Import a markdown file and create a new note with its content
  Future<Note?> importMarkdownFile(String content, String fileName, String notebookId);
  
  /// Export a note to markdown format
  Future<String> exportNoteToMarkdown(String noteId);
}
