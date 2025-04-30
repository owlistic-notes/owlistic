import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nested/nested.dart';
import 'package:thinkstack/services/trash_service.dart';
import '../services/auth_service.dart';
import '../services/note_service.dart';
import '../services/notebook_service.dart';
import '../services/task_service.dart';
import '../services/theme_service.dart';
import '../services/websocket_service.dart';
import '../services/app_state_service.dart';
import '../services/block_service.dart';
import '../utils/document_builder.dart';

// Import ViewModels
import '../viewmodel/notebooks_viewmodel.dart';
import '../viewmodel/notes_viewmodel.dart';
import '../viewmodel/note_editor_viewmodel.dart';
import '../viewmodel/tasks_viewmodel.dart';
import '../viewmodel/theme_viewmodel.dart';
import '../viewmodel/trash_viewmodel.dart';
import '../viewmodel/login_viewmodel.dart';
import '../viewmodel/register_viewmodel.dart';
import '../viewmodel/home_viewmodel.dart';

// ViewModels implementations
import '../providers/notebooks_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/note_editor_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/trash_provider.dart';
import '../providers/login_provider.dart';
import '../providers/register_provider.dart';
import '../providers/home_provider.dart';

/// ServiceLocator for dependency injection
class ServiceLocator {
  static final Map<Type, dynamic> _services = {};

  static void register<T>(T service) {
    _services[T] = service;
  }

  static T get<T>() {
    final service = _services[T];
    if (service == null) {
      throw Exception('Service $T not registered');
    }
    return service as T;
  }
}

/// Initialize all services for the app
void setupServices() {
  // Set up core services first
  final authService = AuthService();
  final webSocketService = WebSocketService();
  final noteService = NoteService();
  final notebookService = NotebookService();
  final taskService = TaskService();
  final themeService = ThemeService();
  final blockService = BlockService();
  final appStateService = AppStateService();
  final trashService = TrashService();

  // Initialize authService explicitly
  authService.initialize();
  webSocketService.initialize();
  
  // Register services in the locator
  ServiceLocator.register<AuthService>(authService);
  ServiceLocator.register<WebSocketService>(webSocketService);
  ServiceLocator.register<NoteService>(noteService);
  ServiceLocator.register<NotebookService>(notebookService);
  ServiceLocator.register<TaskService>(taskService);
  ServiceLocator.register<ThemeService>(themeService);
  ServiceLocator.register<BlockService>(blockService);
  ServiceLocator.register<AppStateService>(appStateService);
  ServiceLocator.register<TrashService>(trashService);
}

/// List of all app providers with proper dependency injection
final List<SingleChildWidget> appProviders = [
  // Services
  Provider<AuthService>(create: (_) => ServiceLocator.get<AuthService>()),
  Provider<WebSocketService>(create: (_) => ServiceLocator.get<WebSocketService>()),
  Provider<NoteService>(create: (_) => ServiceLocator.get<NoteService>()),
  Provider<NotebookService>(create: (_) => ServiceLocator.get<NotebookService>()),
  Provider<TaskService>(create: (_) => ServiceLocator.get<TaskService>()),
  Provider<ThemeService>(create: (_) => ServiceLocator.get<ThemeService>()),
  Provider<BlockService>(create: (_) => ServiceLocator.get<BlockService>()),
  Provider<AppStateService>(create: (_) => ServiceLocator.get<AppStateService>()),
  Provider<TrashService>(create: (_) => ServiceLocator.get<TrashService>()),
  
  // ViewModels
  ChangeNotifierProvider<ThemeViewModel>(
    create: (context) => ThemeProvider(),
  ),
  ChangeNotifierProvider<RegisterViewModel>(
    create: (context) => RegisterProvider(
      authService: context.read<AuthService>(),
      webSocketService: context.read<WebSocketService>(), // Inject WebSocketService directly
    ),
  ),
  ChangeNotifierProvider<LoginViewModel>(
    create: (context) => LoginProvider(
      authService: context.read<AuthService>(),
      webSocketService: context.read<WebSocketService>(), // Inject WebSocketService directly
    ),
  ),
  ChangeNotifierProvider<HomeViewModel>(
    create: (context) => HomeProvider(
      authService: context.read<AuthService>(),
      noteService: context.read<NoteService>(),
      notebookService: context.read<NotebookService>(),
      taskService: context.read<TaskService>(),
      themeService: context.read<ThemeService>(),
      webSocketService: context.read<WebSocketService>(), // Keep directly injecting WebSocketService
    ),
  ),
  ChangeNotifierProvider<NotebooksViewModel>(
    create: (context) => NotebooksProvider(
      notebookService: context.read<NotebookService>(),
      noteService: context.read<NoteService>(),
      authService: context.read<AuthService>(),
      webSocketService: context.read<WebSocketService>(), // Inject WebSocketService directly
    ),
  ),
  ChangeNotifierProvider<NotesViewModel>(
    create: (context) => NotesProvider(
      noteService: context.read<NoteService>(),
      authService: context.read<AuthService>(),
      blockService: context.read<BlockService>(),
      webSocketService: ServiceLocator.get<WebSocketService>(), // Inject WebSocketService directly
    ),
  ),
  ChangeNotifierProvider<TasksViewModel>(
    create: (context) => TasksProvider(
      taskService: context.read<TaskService>(),
      authService: context.read<AuthService>(),
      webSocketService: context.read<WebSocketService>(), // Inject WebSocketService directly
    ),
  ),
  ChangeNotifierProvider<TrashViewModel>(
    create: (context) => TrashProvider(
      authService: context.read<AuthService>(),
      trashService: context.read<TrashService>(),
      webSocketService: context.read<WebSocketService>(),
    ),
  ),
  ChangeNotifierProvider<NoteEditorViewModel>(
    create: (context) => NoteEditorProvider(
      blockService: context.read<BlockService>(),
      authService: context.read<AuthService>(),
      webSocketService: context.read<WebSocketService>(),
      noteService: context.read<NoteService>(),
      documentBuilderFactory: () => DocumentBuilder(),
    ),
  ),
];