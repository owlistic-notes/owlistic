import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/providers.dart';
import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart';
import 'services/auth_service.dart';
import 'services/note_service.dart';
import 'services/notebook_service.dart';
import 'services/block_service.dart';
import 'services/task_service.dart';
import 'services/trash_service.dart';
import 'services/base_service.dart';
import 'services/websocket_service.dart';
import 'utils/logger.dart';

/// Initialize services and load token before starting app
Future<void> initializeServices() async {
  final logger = Logger('AppInit');
  logger.info('Initializing services and loading auth token');
  
  try {
    // Load token from storage
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AuthService.TOKEN_KEY);
    
    if (token != null && token.isNotEmpty) {
      logger.info('Found existing auth token, initializing services with it');
      
      // Create auth service instance
      final authService = AuthService();
      
      // Register the service in the locator
      ServiceLocator.register<AuthService>(authService);
      
      // This will update BaseService's token
      await authService.onTokenChanged(token);
    } else {
      logger.info('No auth token found, app will start unauthenticated');
      
      // Still register the auth service
      final authService = AuthService();
      ServiceLocator.register<AuthService>(authService);
    }
    
    logger.info('Services initialized successfully');
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
