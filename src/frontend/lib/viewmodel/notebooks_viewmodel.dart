import 'package:owlistic/models/notebook.dart';
import 'package:owlistic/models/note.dart';
import 'base_viewmodel.dart';

/// Interface for notebook management functionality
abstract class NotebooksViewModel extends BaseViewModel {
  /// All notebooks
  List<Notebook> get notebooks;
  
  /// Get notebooks with optional filtering
  Future<void> fetchNotebooks({
    String? name, 
    int page = 1, 
    int pageSize = 20,
    List<String>? excludeIds,
  });
  
  /// Get a specific notebook by ID with its notes
  Future<Notebook?> fetchNotebookById(String id, {
    List<String>? excludeIds,
    bool addToExistingList = false,
    bool updateExisting = false
  });
  
  /// Create a new notebook
  Future<Notebook?> createNotebook(String name, String description);
  
  /// Update a notebook
  Future<Notebook?> updateNotebook(String id, String name, String description);
  
  /// Delete a notebook
  Future<void> deleteNotebook(String id);
  
  /// Add a note to a notebook
  Future<Note?> addNoteToNotebook(String notebookId, String title);
  
  /// Delete a note from a notebook
  Future<void> deleteNote(String notebookId, String noteId);
  
  /// Get a notebook by ID from cache
  Notebook? getNotebook(String id);
  
  /// Update the notebooks list directly
  void updateNotebooksList(List<Notebook> updatedNotebooks);
  
  /// Update just the notes collection of a specific notebook
  void updateNotebookNotes(String notebookId, List<Note> updatedNotes);
  
  /// Remove a notebook by ID
  void removeNotebookById(String notebookId);
}
