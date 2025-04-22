import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/block_provider.dart';
import '../providers/notebooks_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/trash_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/websocket_provider.dart';
import '../services/auth_service.dart';
import '../services/block_service.dart';
import '../services/note_service.dart';
import '../services/notebook_service.dart';
import '../services/task_service.dart';
import '../services/trash_service.dart';
import '../services/base_service.dart';
import '../services/websocket_service.dart';
import 'package:provider/single_child_widget.dart';

/// List of all app providers with proper dependency injection
final List<SingleChildWidget> appProviders = [
  // Auth provider
  ChangeNotifierProvider(
    create: (context) => AuthProvider(
      authService: ServiceLocator.get<AuthService>()
    ),
  ),
  
  // Theme provider
  ChangeNotifierProvider(
    create: (context) => ThemeProvider(),
  ),
  
  // WebSocket provider with dependencies
  ChangeNotifierProvider(
    create: (context) => WebSocketProvider(
      webSocketService: ServiceLocator.get<WebSocketService>(),
      authService: ServiceLocator.get<AuthService>()
    ),
  ),
  
  // Notes provider
  ChangeNotifierProvider(
    create: (context) => NotesProvider(
      noteService: ServiceLocator.get<NoteService>(),
      authService: ServiceLocator.get<AuthService>(),
      blockService: ServiceLocator.get<BlockService>()
    ),
  ),
  
  // Notebooks provider
  ChangeNotifierProvider(
    create: (context) => NotebooksProvider(
      notebookService: ServiceLocator.get<NotebookService>(),
      noteService: ServiceLocator.get<NoteService>(),
      authService: ServiceLocator.get<AuthService>()
    ),
  ),
  
  // Tasks provider
  ChangeNotifierProvider(
    create: (context) => TasksProvider(
      taskService: ServiceLocator.get<TaskService>(),
      authService: ServiceLocator.get<AuthService>()
    ),
  ),
  
  // Block provider
  ChangeNotifierProvider(
    create: (context) => BlockProvider(
      blockService: ServiceLocator.get<BlockService>(),
      authService: ServiceLocator.get<AuthService>()
    ),
  ),
  
  // Trash provider
  ChangeNotifierProvider(
    create: (context) => TrashProvider(
      trashService: ServiceLocator.get<TrashService>(),
      authService: ServiceLocator.get<AuthService>()
    ),
  ),
];
