import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:owlistic/core/router.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'core/providers.dart';

import 'services/auth_service.dart';
import 'services/block_service.dart';
import 'services/note_service.dart';
import 'services/notebook_service.dart';
import 'services/task_service.dart';
import 'services/trash_service.dart';
import 'services/websocket_service.dart';
import 'services/app_state_service.dart';

import 'utils/logger.dart';
import 'viewmodel/login_viewmodel.dart';
import 'viewmodel/theme_viewmodel.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  final logger = Logger('Main');
  logger.info('Starting Owlistic application');
  
  try {
    // Initialize ServiceLocator explicitly before creating any providers
    setupServices();
    logger.info('ServiceLocator initialized successfully');

    // Initialize core services in correct order before providers
    _initializeServices();
    logger.info('Core services initialized successfully');
    
    runApp(OwlisticApp());
  } catch (e) {
    logger.error('Failed to initialize application: $e');
    runApp(ErrorApp(message: e.toString()));
  }
}

// Initialize services in the proper order
void _initializeServices() {
  // Initialize WebSocketService first since providers depend on it
  final webSocketService = WebSocketService();
  webSocketService.initialize();
  
  // Initialize AppStateService
  final appStateService = AppStateService();
  
  // Initialize AuthService (registers itself as singleton)
  final authService = AuthService();
  
  // You could register these in ServiceLocator if needed
  ServiceLocator.register<WebSocketService>(webSocketService);
  ServiceLocator.register<AppStateService>(appStateService);
  ServiceLocator.register<AuthService>(authService);
  
  // Register other core services
  ServiceLocator.register<NoteService>(NoteService());
  ServiceLocator.register<NotebookService>(NotebookService());
  ServiceLocator.register<BlockService>(BlockService());
  ServiceLocator.register<TaskService>(TaskService());
  ServiceLocator.register<TrashService>(TrashService());
}

class OwlisticApp extends StatelessWidget {
  final Logger _logger = Logger('OwlisticApp');
  
  OwlisticApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: appProviders,
      child: const OwlisticAppWithProviders(),
    );
  }
}

class OwlisticAppWithProviders extends StatefulWidget {
  const OwlisticAppWithProviders({Key? key}) : super(key: key);

  @override
  _OwlisticAppWithProvidersState createState() => _OwlisticAppWithProvidersState();
}

class _OwlisticAppWithProvidersState extends State<OwlisticAppWithProviders> {
  final Logger _logger = Logger('OwlisticAppState');
  late final AppRouter _appRouter;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _appRouter = AppRouter(
      context, 
      authStateChanges: context.read<LoginViewModel>().authStateChanges
    );
    _router = _appRouter.router;
  }

  @override
  Widget build(BuildContext context) {
    // Listen to theme changes
    return Consumer<ThemeViewModel>(
      builder: (context, themeViewModel, _) {
        return MaterialApp.router(
          title: 'Owlistic',
          debugShowCheckedModeBanner: false,
          theme: themeViewModel.theme,
          themeMode: themeViewModel.themeMode,
          darkTheme: AppTheme.darkTheme,
          routerConfig: _router,
        );
      },
    );
  }
}

// Error app for initialization failures
class ErrorApp extends StatelessWidget {
  final String message;
  
  const ErrorApp({Key? key, required this.message}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Failed to start application',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    // Attempt to restart the app
                    main();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
