import 'package:flutter/material.dart';
import 'package:owlistic/models/block.dart';
import 'package:owlistic/models/note.dart';
import 'package:owlistic/utils/document_builder.dart';
import 'base_viewmodel.dart';

abstract class NoteEditorViewModel extends BaseViewModel {
  // Note properties
  String? get noteId;
  set noteId(String? value);
  List<Block> get blocks;
  int get updateCount;
  
  // Note object
  Note? get currentNote;
  
  // Note operations (moved from NotesViewModel)
  Future<Note?> fetchNoteById(String id);
  Future<Note> updateNoteTitle(String id, String title);
  
  // Block operations
  Block? getBlock(String id);
  List<Block> getBlocksForNote(String noteId);
  Future<List<Block>> fetchBlocksForNote(String noteId, {
    int page = 1,
    int pageSize = 100,
    bool append = false,
    bool refresh = false
  });
  Future<Block?> fetchBlockById(String blockId);
  Future<void> deleteBlock(String blockId);
  void updateBlock(String id, Map<String, dynamic> content, {
    String? type, 
    double? order,
  });
  
  // Document builder access
  DocumentBuilder get documentBuilder;
  FocusNode get focusNode;
  
  // Document management
  void setBlocks(List<Block> blocks);
  void addBlocks(List<Block> blocks);
  
  // Active note management
  void activateNote(String noteId);
  void deactivateNote(String noteId);
  
  // Block visibility and pagination 
  
  /// Subscribe to receive updates for specific block IDs that are visible in the UI.
  /// This optimizes websocket subscriptions to focus on currently visible blocks.
  void subscribeToVisibleBlocks(String noteId, List<String> visibleBlockIds);
  
  /// Check if there are more blocks available to load for the given note.
  bool hasMoreBlocks(String noteId);
  
  /// Get current pagination information for the specified note.
  Map<String, dynamic> getPaginationInfo(String noteId);
  
  // Server sync and events
  void commitAllNodes();
  Future<void> fetchBlockFromEvent(String blockId);
  
  // Focus handling
  void requestFocus();
  void setFocusToBlock(String blockId);
  String? consumeFocusRequest();
  
  void redo() {}
  void undo() {}

  // User modified blocks tracking
  Set<String> get userModifiedBlockIds;
  
  // Pagination scroll handling
  
  /// Initializes the scroll listener for pagination.
  /// This should be called when the note editor is initialized.
  /// The provided ScrollController will be used to detect when the user 
  /// scrolls near the bottom to automatically load more blocks.
  void initScrollListener(ScrollController scrollController);
}
