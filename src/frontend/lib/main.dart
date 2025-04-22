import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thinkstack/core/providers.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/notes_provider.dart';
import 'providers/notebooks_provider.dart';
import 'providers/tasks_provider.dart';
import 'providers/block_provider.dart';
import 'providers/trash_provider.dart';
import 'providers/websocket_provider.dart';
import 'services/auth_service.dart';
import 'services/note_service.dart';
import 'services/notebook_service.dart';
import 'services/block_service.dart';
import 'services/task_service.dart';
import 'services/trash_service.dart';
import 'services/websocket_service.dart';
import 'services/base_service.dart';
import 'utils/logger.dart';

/// Initialize services and load token before starting app
Future<void> initializeServices() async {
  final logger = Logger('AppInit');
  logger.info('Initializing services and loading auth token');
  
  try {
    // Create service instances
    final authService = AuthService();
    final noteService = NoteService();
    final notebookService = NotebookService();
    final blockService = BlockService();
    final taskService = TaskService();
    final trashService = TrashService();
    final websocketService = WebSocketService();
    
    // Register services in ServiceLocator
    ServiceLocator.register<AuthService>(authService);
    ServiceLocator.register<NoteService>(noteService);
    ServiceLocator.register<NotebookService>(notebookService);
    ServiceLocator.register<BlockService>(blockService);
    ServiceLocator.register<TaskService>(taskService);
    ServiceLocator.register<TrashService>(trashService);
    ServiceLocator.register<WebSocketService>(websocketService);
    
    // Load token from storage
    // final token = await authService.getStoredToken();
    
    // if (token != null && token.isNotEmpty) {
    //   logger.info('Found existing auth token, initializing services with it');
      
    //   try {
    //     await authService.onTokenChanged(token);
    //     logger.info('Authentication token successfully initialized');
    //   } catch (e) {
    //     logger.error('Failed to initialize with stored token, clearing it', e);
    //     await authService.clearToken();
    //   }
    // } else {
    //   logger.info('No auth token found, app will start unauthenticated');
    // }
    
    // logger.info('Services initialized successfully');
  } catch (e) {
    logger.error('Error initializing services', e);
  }
}

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Setup error handling for Flutter errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    Logger('FlutterError').error('Uncaught Flutter error', details.exception, details.stack);
  };
  
  // Error handling for asynchronous errors
  // This catches errors that occur outside the Flutter framework
  PlatformDispatcher.instance.onError = (error, stack) {
    Logger('PlatformError').error('Uncaught platform error', error, stack);
    return true;
  };
  
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  // Initialize services and load token
  await initializeServices();
  
  // Start the app
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Create providers using consistent dependency injection pattern
    return MultiProvider(
      providers: [
        ...appProviders,
      ],
      child: Builder(
        builder: (context) {
          // Use Provider.of with listen: false to prevent rebuild loops
          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          final router = AppRouter.createRouter(authProvider);
          
          return Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) => MaterialApp.router(
              title: 'ThinkStack',
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeProvider.themeMode,
              routerConfig: router,
              debugShowCheckedModeBanner: false,
              // Add error handling for router/navigation errors
              builder: (context, child) {
                // Add error boundary widget here if needed
                return child ?? const SizedBox.shrink();
              },
            ),
          );
        }
      ),
    );
  }
}
