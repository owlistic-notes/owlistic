import 'package:flutter/material.dart';
import '../providers/notes_provider.dart';
import '../providers/notebooks_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/block_provider.dart';

/// A utility class to coordinate WebSocket events between providers
/// This avoids direct dependencies between providers
class WebSocketEventCoordinator {
  // Singleton instance
  static final WebSocketEventCoordinator _instance = WebSocketEventCoordinator._internal();
  factory WebSocketEventCoordinator() => _instance;
  WebSocketEventCoordinator._internal();

  // Provider references
  NotesProvider? _notesProvider;
  NotebooksProvider? _notebooksProvider;
  TasksProvider? _tasksProvider;
  BlockProvider? _blockProvider;

  // Register providers
  void registerNotesProvider(NotesProvider provider) => _notesProvider = provider;
  void registerNotebooksProvider(NotebooksProvider provider) => _notebooksProvider = provider;
  void registerTasksProvider(TasksProvider provider) => _tasksProvider = provider;
  void registerBlockProvider(BlockProvider provider) => _blockProvider = provider;

  // Handle entity creation
  void handleEntityCreated(String type, String id) {
    debugPrint('WebSocketEventCoordinator: Entity created - $type:$id');
    
    switch (type) {
      case 'note':
        _notesProvider?.addNoteFromEvent(id);
        break;
      case 'notebook':
        _notebooksProvider?.addNotebookFromEvent(id);
        break;
      case 'task':
        _tasksProvider?.addTaskFromEvent(id);
        break;
      case 'block':
        _blockProvider?.addBlockFromEvent(id);
        break;
    }
  }
  
  // Handle entity updated
  void handleEntityUpdated(String type, String id) {
    debugPrint('WebSocketEventCoordinator: Entity updated - $type:$id');
    
    switch (type) {
      case 'note':
        _notesProvider?.fetchNoteById(id);
        break;
      case 'notebook':
        _notebooksProvider?.fetchNotebookById(id);
        break;
      case 'task':
        _tasksProvider?.fetchTaskFromEvent(id);
        break;
      case 'block':
        _blockProvider?.fetchBlockFromEvent(id);
        break;
    }
  }
  
  // Handle entity deleted
  void handleEntityDeleted(String type, String id) {
    debugPrint('WebSocketEventCoordinator: Entity deleted - $type:$id');
    
    switch (type) {
      case 'note':
        _notesProvider?.handleNoteDeleted(id);
        break;
      case 'notebook':
        _notebooksProvider?.handleNotebookDeleted(id);
        break;
      case 'task':
        _tasksProvider?.handleTaskDeleted(id);
        break;
      case 'block':
        _blockProvider?.handleBlockDeleted(id);
        break;
    }
  }
}
