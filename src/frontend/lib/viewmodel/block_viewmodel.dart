import 'package:flutter/material.dart';
import '../models/block.dart';
import 'base_viewmodel.dart';

abstract class BlockViewModel extends BaseViewModel {
  // Existing getters
  List<Block> get allBlocks;
  int get updateCount;
  Block? getBlock(String id);
  List<Block> getBlocksForNote(String noteId);
  
  // Fetch operations
  Future<List<Block>> fetchBlocksForNote(String noteId, {
    int page = 1,
    int pageSize = 100,
    bool append = false,
    bool refresh = false
  });
  Future<Block?> fetchBlockById(String blockId);
  
  // Adding missing modify operations
  Future<Block> createBlock(String noteId, dynamic content, String type, double order);
  Future<void> deleteBlock(String blockId);
  void updateBlockContent(String id, dynamic content, {
    String? type, 
    double? order,
    bool immediate = false,
    bool updateLocalOnly = false
  });
  
  // Note activation methods
  void activateNote(String noteId);
  void deactivateNote(String noteId);
  
  // Block visibility subscriptions
  void subscribeToVisibleBlocks(String noteId, List<String> visibleBlockIds);
  
  // Pagination helpers
  bool hasMoreBlocks(String noteId);
  Map<String, dynamic> getPaginationInfo(String noteId);

  // Implementation detail methods needed by screens (should be private in provider)
  Future<void> addBlockFromEvent(String blockId);
  Future<void> fetchBlockFromEvent(String blockId);
}
