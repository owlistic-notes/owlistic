import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/notebooks_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/block_provider.dart';
import '../providers/rich_text_editor_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/trash_provider.dart';
import '../providers/websocket_provider.dart';
import '../services/auth_service.dart';
import '../services/note_service.dart';
import '../services/notebook_service.dart';
import '../services/block_service.dart';
import '../services/task_service.dart';
import '../services/trash_service.dart';
import '../services/websocket_service.dart';
import '../utils/logger.dart';

final Logger _logger = Logger('Providers');

/// List of all providers used in the app
List<SingleChildWidget> get appProviders {
  try {
    // Create services first
    final authService = AuthService();
    final noteService = NoteService();
    final notebookService = NotebookService();
    final blockService = BlockService();
    final taskService = TaskService();
    final trashService = TrashService();
    final websocketService = WebSocketService();

    return [
      // Service providers
      Provider<AuthService>(
        create: (_) => authService,
      ),
      Provider<NoteService>(
        create: (_) => noteService,
      ),
      Provider<NotebookService>(
        create: (_) => notebookService,
      ),
      Provider<BlockService>(
        create: (_) => blockService,
      ),
      Provider<TaskService>(
        create: (_) => taskService,
      ),
      Provider<TrashService>(
        create: (_) => trashService,
      ),
      Provider<WebSocketService>(
        create: (_) => websocketService,
      ),

      // Auth provider comes first (as it's used by others)
      ChangeNotifierProvider<AuthProvider>(
        create: (context) {
          _logger.info("Creating AuthProvider");
          try {
            return AuthProvider(authService: authService);
          } catch (e) {
            _logger.error("Error creating AuthProvider", e);
            throw e;
          }
        }
      ),
      
      // Theme provider
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
      ),
      
      // WebSocket provider comes next (as it's used by other providers)
      ChangeNotifierProxyProvider<AuthProvider, WebSocketProvider>(
        create: (context) {
          _logger.info("Creating WebSocketProvider without auth");
          try {
            // Initial creation without auth dependency
            return WebSocketProvider(
              webSocketService: websocketService, 
              authService: authService
            );
          } catch (e) {
            _logger.error("Error creating WebSocketProvider", e);
            throw e;
          }
        },
        update: (context, auth, previous) {
          // If we already have a previous instance and auth state hasn't changed, keep it
          if (previous != null && previous.currentUser?.id == auth.currentUser?.id) {
            _logger.debug("Reusing existing WebSocketProvider");
            return previous;
          }

          _logger.info("Updating WebSocketProvider with AuthProvider");
          try {
            if (previous != null) {
              // Update user ID in the existing instance
              if (auth.currentUser != null) {
                _logger.info("Setting WebSocket user ID: ${auth.currentUser!.id}");
                websocketService.setUserId(auth.currentUser!.id);
                previous.connect();
              } else {
                previous.disconnect();
              }
              return previous;
            } else {
              // Create a new instance with auth dependency
              return WebSocketProvider(
                webSocketService: websocketService,
                authService: authService
              );
            }
          } catch (e) {
            _logger.error("Error updating WebSocketProvider", e);
            throw e;
          }
        }
      ),
      
      // Create NotebooksProvider after WebSocketProvider
      ChangeNotifierProxyProvider<WebSocketProvider, NotebooksProvider>(
        create: (context) {
          _logger.info("Creating NotebooksProvider");
          try {
            final notebooksProvider = NotebooksProvider(
              notebookService: notebookService,
              noteService: noteService,
              authService: authService,
            );
            
            return notebooksProvider;
          } catch (e) {
            _logger.error("Error creating NotebooksProvider", e);
            throw e;
          }
        },
        update: (context, wsProvider, previous) {
          try {
            // If we have a previous instance, update it
            if (previous != null) {
              // Set WebSocketProvider and activate if user is logged in
              previous.setWebSocketProvider(wsProvider);
              
              // Fetch notebooks if user is logged in
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              if (authProvider.isLoggedIn) {
                _logger.info("User is logged in, ensuring NotebooksProvider is activated");
                previous.activate();
              }
              
              return previous;
            } else {
              // Create a new instance
              final notebooksProvider = NotebooksProvider(
                notebookService: notebookService,
                noteService: noteService,
                authService: authService,
              );
              
              notebooksProvider.setWebSocketProvider(wsProvider);
              return notebooksProvider;
            }
          } catch (e) {
            _logger.error("Error updating NotebooksProvider", e);
            throw e;
          }
        },
      ),
      
      // Notes provider
      ChangeNotifierProvider<NotesProvider>(
        create: (context) {
          _logger.info("Creating NotesProvider");
          try {
            final notesProvider = NotesProvider(
              noteService: noteService,
              authService: authService,
            );
            
            final wsProvider = Provider.of<WebSocketProvider>(context, listen: false);
            notesProvider.setWebSocketProvider(wsProvider);
            
            return notesProvider;
          } catch (e) {
            _logger.error("Error creating NotesProvider", e);
            throw e;
          }
        },
      ),
      
      // Block provider
      ChangeNotifierProvider<BlockProvider>(
        create: (context) {
          _logger.info("Creating BlockProvider");
          try {
            final blockProvider = BlockProvider(
              blockService: blockService,
              authService: authService,
            );
            
            final wsProvider = Provider.of<WebSocketProvider>(context, listen: false);
            blockProvider.setWebSocketProvider(wsProvider);
            
            return blockProvider;
          } catch (e) {
            _logger.error("Error creating BlockProvider", e);
            throw e;
          }
        },
      ),
      
      // Tasks provider
      ChangeNotifierProvider<TasksProvider>(
        create: (context) {
          _logger.info("Creating TasksProvider");
          try {
            final tasksProvider = TasksProvider(
              taskService: taskService,
              authService: authService,
            );
            
            final wsProvider = Provider.of<WebSocketProvider>(context, listen: false);
            tasksProvider.setWebSocketProvider(wsProvider);
            
            return tasksProvider;
          } catch (e) {
            _logger.error("Error creating TasksProvider", e);
            throw e;
          }
        },
      ),
      
      // Trash provider
      ChangeNotifierProvider<TrashProvider>(
        create: (context) {
          _logger.info("Creating TrashProvider");
          try {
            final trashProvider = TrashProvider(
              trashService: trashService
            );
            
            final wsProvider = Provider.of<WebSocketProvider>(context, listen: false);
            trashProvider.setWebSocketProvider(wsProvider);
            
            return trashProvider;
          } catch (e) {
            _logger.error("Error creating TrashProvider", e);
            throw e;
          }
        },
      ),
    ];
  } catch (e) {
    _logger.error("Error setting up providers", e);
    throw e;
  }
}
