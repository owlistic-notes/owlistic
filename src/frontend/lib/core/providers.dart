import 'package:provider/provider.dart';

// Import ViewModels
import '../viewmodel/auth_viewmodel.dart';
import '../viewmodel/notebooks_viewmodel.dart';
import '../viewmodel/notes_viewmodel.dart';
import '../viewmodel/note_editor_viewmodel.dart';  // New unified viewmodel
import '../viewmodel/tasks_viewmodel.dart';
import '../viewmodel/theme_viewmodel.dart';
import '../viewmodel/trash_viewmodel.dart';
import '../viewmodel/websocket_viewmodel.dart';

// ViewModels implementations
import '../providers/auth_provider.dart';
import '../providers/notebooks_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/note_editor_provider.dart';  // New unified provider
import '../providers/tasks_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/trash_provider.dart';
import '../providers/websocket_provider.dart';

// Services - these remain the same in MVVM
import '../services/auth_service.dart';
import '../services/block_service.dart';
import '../services/app_state_service.dart';
import '../services/note_service.dart';
import '../services/notebook_service.dart';
import '../services/task_service.dart';
import '../services/trash_service.dart';
import '../services/websocket_service.dart';

// Import utilities
import '../utils/logger.dart';
import '../utils/document_builder.dart';
import 'package:provider/single_child_widget.dart';

/// List of all app providers with proper dependency injection
/// Following MVVM pattern, ViewModels depend on services, not other ViewModels
final List<SingleChildWidget> appProviders = [
  // First provide the services directly
  Provider<WebSocketService>(
    create: (_) => WebSocketService(),
  ),
  
  Provider<AuthService>(
    create: (_) => AuthService(),
  ),
  
  Provider<AppStateService>(
    create: (_) => AppStateService(),
  ),
  
  // Then create the providers that depend on services
  ChangeNotifierProvider<AuthViewModel>(
    create: (context) => AuthProvider(
      authService: context.read<AuthService>(),
      appStateService: context.read<AppStateService>(),
    ),
  ),
  
  // Theme view model
  ChangeNotifierProvider<ThemeViewModel>(
    create: (context) => ThemeProvider(),
  ),
  
  // WebSocket view model with dependencies
  ChangeNotifierProvider<WebSocketViewModel>(
    create: (context) => WebSocketProvider(
      webSocketService: ServiceLocator.get<WebSocketService>(),
      authService: context.read<AuthService>()
    ),
  ),
  
  // Notes view model
  ChangeNotifierProvider<NotesViewModel>(
    create: (context) => NotesProvider(
      noteService: ServiceLocator.get<NoteService>(),
      authService: ServiceLocator.get<AuthService>(),
      blockService: ServiceLocator.get<BlockService>()
    ),
  ),
  
  // Notebooks view model
  ChangeNotifierProvider<NotebooksViewModel>(
    create: (context) => NotebooksProvider(
      notebookService: ServiceLocator.get<NotebookService>(),
      noteService: ServiceLocator.get<NoteService>(),
      authService: ServiceLocator.get<AuthService>()
    ),
  ),
  
  // Tasks view model
  ChangeNotifierProvider<TasksViewModel>(
    create: (context) => TasksProvider(
      taskService: ServiceLocator.get<TaskService>(),
      authService: ServiceLocator.get<AuthService>()
    ),
  ),
  
  // Note Editor view model
  ChangeNotifierProvider<NoteEditorViewModel>(
    create: (context) => NoteEditorProvider(
      blockService: ServiceLocator.get<BlockService>(),
      authService: ServiceLocator.get<AuthService>(),
      webSocketService: ServiceLocator.get<WebSocketService>(),
      noteService: ServiceLocator.get<NoteService>(),
      documentBuilderFactory: () => DocumentBuilder()
    ),
  ),
  
  // Trash view model
  ChangeNotifierProvider<TrashViewModel>(
    create: (context) => TrashProvider(
      trashService: ServiceLocator.get<TrashService>(),
      authService: ServiceLocator.get<AuthService>()
    ),
  ),
];


/// Service locator pattern implementation for dependency injection
class ServiceLocator {
  static final Map<Type, dynamic> _services = {};
  static final Logger _logger = Logger('ServiceLocator');
  static bool _isInitialized = false;

  /// Get a service instance by type
  static T get<T>() {
    if (!_isInitialized) {
      _logger.error('ServiceLocator not initialized before accessing ${T.toString()}');
      throw Exception('ServiceLocator not initialized');
    }
    
    if (!_services.containsKey(T)) {
      _logger.error('Service of type $T not registered');
      throw Exception('Service not found: $T');
    }
    return _services[T] as T;
  }

  /// Check if a service type is registered
  static bool isRegistered<T>() {
    return _services.containsKey(T);
  }
  
  /// Check if ServiceLocator has been initialized
  static bool isInitialized() {
    return _isInitialized;
  }

  /// Register a service instance
  static void register<T>(T service) {
    _logger.debug('Registering service: ${T.toString()}');
    _services[T] = service;
  }

  /// Initialize all services
  static Future<void> initialize() async {
    if (_isInitialized) {
      _logger.info('ServiceLocator already initialized, skipping');
      return;
    }

    _logger.info('Initializing services...');
    
    try {
      // Register all services
      register<AppStateService>(AppStateService());
      register<AuthService>(AuthService());
      register<WebSocketService>(WebSocketService());
      register<NotebookService>(NotebookService());
      register<NoteService>(NoteService());
      register<BlockService>(BlockService());
      register<TaskService>(TaskService());
      register<TrashService>(TrashService());
      
      // Initialize AuthService, which will set the token in BaseService
      final authService = _services[AuthService] as AuthService;
      await authService.getStoredToken(); // This will load the token
      _logger.info('AuthService token loaded');
      
      // Mark as initialized now that core services are ready
      _isInitialized = true;
      _logger.info('All services initialized successfully');
    } catch (e) {
      _logger.error('Error initializing services: $e');
      throw Exception('Failed to initialize services: $e');
    }
  }
}