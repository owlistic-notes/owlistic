import 'package:flutter/material.dart';
import '../models/block.dart';
import '../models/note.dart';
import '../utils/document_builder.dart';
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
  Future<Block> createBlock(String type);
  Future<void> deleteBlock(String blockId);
  void updateBlockContent(String id, dynamic content, {
    String? type, 
    double? order,
    bool immediate = false,
    bool updateLocalOnly = false
  });
  
  // Document builder access
  DocumentBuilder get documentBuilder;
  FocusNode get focusNode;
  
  // Document management
  void setBlocks(List<Block> blocks);
  void updateBlocks(List<Block> blocks, {
    bool preserveFocus = false,
    dynamic savedSelection,
    bool markAsModified = true
  });
  void addBlocks(List<Block> blocks);
  
  // Active note management
  void activateNote(String noteId);
  void deactivateNote(String noteId);
  
  // Block visibility and pagination
  void subscribeToVisibleBlocks(String noteId, List<String> visibleBlockIds);
  bool hasMoreBlocks(String noteId);
  Map<String, dynamic> getPaginationInfo(String noteId);
  
  // Server sync and events
  void updateBlockCache(List<Block> blocks);
  void commitAllContent();
  void markBlockAsModified(String blockId);
  Future<void> fetchBlockFromEvent(String blockId);
  
  // Focus handling
  void requestFocus();
  void setFocusToBlock(String blockId);
  String? consumeFocusRequest();
  
  // User modified blocks tracking
  Set<String> get userModifiedBlockIds;
}
