import 'package:owlistic/models/note.dart';
import 'package:owlistic/models/notebook.dart';
import 'base_viewmodel.dart';

/// Interface for trash management functionality
abstract class TrashViewModel extends BaseViewModel {
  /// Trashed notes
  List<Note> get trashedNotes;
  
  /// Trashed notebooks
  List<Notebook> get trashedNotebooks;
  
  /// Fetch all trashed items
  Future<void> fetchTrashedItems();
  
  /// Restore an item from trash
  Future<void> restoreItem(String type, String id);
  
  /// Permanently delete an item from trash
  Future<void> permanentlyDeleteItem(String type, String id);
  
  /// Empty the entire trash
  Future<void> emptyTrash();
}
