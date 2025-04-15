import 'package:flutter/material.dart';
import '../models/note.dart';
import '../models/notebook.dart';
import '../services/api_service.dart';

class NotebooksProvider with ChangeNotifier {
  List<Notebook> _notebooks = [];
  bool _isLoading = false;

  List<Notebook> get notebooks => [..._notebooks];
  bool get isLoading => _isLoading;

  Future<void> fetchNotebooks() async {
    _isLoading = true;
    notifyListeners();

    try {
      _notebooks = await ApiService.fetchNotebooks();
    } catch (error) {
      print('Error fetching notebooks: $error');
      _notebooks = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> createNotebook(String name, String description) async {
    try {
      final notebook = await ApiService.createNotebook(name, description);
      _notebooks.add(notebook);
      notifyListeners();
    } catch (error) {
      print('Error creating notebook: $error');
      rethrow;
    }
  }

  Future<void> addNoteToNotebook(String notebookId, String title) async {
    try {
      final note = await ApiService.createNote(notebookId, title);
      final index = _notebooks.indexWhere((nb) => nb.id == notebookId);
      if (index != -1) {
        final updatedNotebook = _notebooks[index];
        final notes = List<Note>.from(updatedNotebook.notes)..add(note);
        _notebooks[index] = Notebook(
          id: updatedNotebook.id,
          name: updatedNotebook.name,
          description: updatedNotebook.description,
          userId: updatedNotebook.userId,
          notes: notes,
        );
        notifyListeners();
      }
    } catch (error) {
      print('Error adding note to notebook: $error');
      rethrow;
    }
  }

  Future<void> deleteNoteFromNotebook(String notebookId, String noteId) async {
    try {
      await ApiService.deleteNoteFromNotebook(notebookId, noteId);
      final index = _notebooks.indexWhere((nb) => nb.id == notebookId);
      if (index != -1) {
        final updatedNotebook = _notebooks[index];
        final notes = updatedNotebook.notes.where((note) => note.id != noteId).toList();
        _notebooks[index] = Notebook(
          id: updatedNotebook.id,
          name: updatedNotebook.name,
          description: updatedNotebook.description,
          userId: updatedNotebook.userId,
          notes: notes,
        );
        notifyListeners();
      }
    } catch (error) {
      print('Error deleting note from notebook: $error');
      rethrow;
    }
  }

  Future<void> updateNotebook(String id, String name, String description) async {
    try {
      final notebook = await ApiService.updateNotebook(id, name, description);
      final index = _notebooks.indexWhere((nb) => nb.id == id);
      if (index != -1) {
        _notebooks[index] = notebook;
        notifyListeners();
      }
    } catch (error) {
      print('Error updating notebook: $error');
      rethrow;
    }
  }

  Future<void> deleteNotebook(String id) async {
    try {
      await ApiService.deleteNotebook(id);
      _notebooks.removeWhere((notebook) => notebook.id == id);
      notifyListeners();
    } catch (error) {
      print('Error deleting notebook: $error');
      rethrow;
    }
  }
}
