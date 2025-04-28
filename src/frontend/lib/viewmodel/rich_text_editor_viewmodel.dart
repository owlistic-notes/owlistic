import 'package:flutter/material.dart';
import '../models/block.dart';
import '../utils/document_builder.dart';
import 'base_viewmodel.dart';

abstract class RichTextEditorViewModel extends BaseViewModel {
  // Document properties
  String? get noteId;
  set noteId(String? value);
  List<Block> get blocks;
  
  // Focus control
  FocusNode get focusNode;
  
  // DocumentBuilder access - use this instead of direct document/composer access
  DocumentBuilder get documentBuilder;
  
  // Block update methods
  void setBlocks(List<Block> blocks);
  void updateBlocks(List<Block> blocks, {
    bool preserveFocus = false,
    dynamic savedSelection,
    bool markAsModified = true
  });
  void addBlocks(List<Block> blocks);
  
  // Server sync methods
  void updateBlockCache(List<Block> blocks);
  void commitAllContent();
  void markBlockAsModified(String blockId);
  
  // Event callbacks
  set onBlockContentChanged(void Function(String blockId, dynamic content)? callback);
  set onBlockDeleted(void Function(String blockId)? callback);
  set onMultiBlockOperation(void Function(List<String> blockIds)? callback);
  set onFocusLost(void Function()? callback);
  
  // UI helpers
  void requestFocus();
  void setFocusToBlock(String blockId);
  String? consumeFocusRequest();
  
  // Block operations
  Future<Block> createBlock(String type);
  void deleteBlock(String blockId);
  
  // Expose user-modified blocks
  Set<String> get userModifiedBlockIds;
}
