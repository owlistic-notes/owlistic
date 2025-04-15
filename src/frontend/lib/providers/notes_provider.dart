import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/api_service.dart';

class NotesProvider with ChangeNotifier {
  List<Note> _notes = [];
  bool _isLoading = false;

  List<Note> get notes => [..._notes];
  bool get isLoading => _isLoading;
  List<Note> get recentNotes => _notes.take(3).toList();

  Future<void> fetchNotes() async {
    _isLoading = true;
    notifyListeners();

    try {
      _notes = await ApiService.fetchNotes();
      print('Fetched ${_notes.length} notes');
      print('First note: ${_notes.isNotEmpty ? _notes.first.title : "no notes"}');
    } catch (error) {
      print('Error fetching notes: $error');
      _notes = []; // Ensure notes is empty on error
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> createNote(String notebookId, String title) async {
    try {
      final note = await ApiService.createNote(notebookId, title);
      _notes.add(note);
      notifyListeners();
    } catch (error) {
      print('Error creating note: $error');
      rethrow;
    }
  }

  Future<void> deleteNote(String id) async {
    try {
      await ApiService.deleteNote(id);
      _notes.removeWhere((note) => note.id == id);
      notifyListeners();
    } catch (error) {
      print('Error deleting note: $error');
      rethrow;
    }
  }

  Future<void> updateNote(String id, String title) async {
    try {
      final updatedNote = await ApiService.updateNote(id, title);
      final index = _notes.indexWhere((note) => note.id == id);
      if (index != -1) {
        _notes[index] = updatedNote;
        notifyListeners();
      }
    } catch (error) {
      print('Error updating note: $error');
      rethrow;
    }
  }
}
