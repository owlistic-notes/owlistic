import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/home_screen.dart';
import '../screens/notebooks_screen.dart';
import '../screens/notebook_detail_screen.dart';
import '../screens/notes_screen.dart';
import '../screens/tasks_screen.dart';
import '../screens/trash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/register_screen.dart';
import '../utils/logger.dart';

/// App Router definition using GoRouter
class AppRouter {
  // Use logging to aid debugging
  static final Logger _logger = Logger('AppRouter');
  
  // Create a navigator key to access the current context
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  // Create router with redirection logic
  static GoRouter createRouter(AuthProvider authProvider) {
    return GoRouter(
      navigatorKey: navigatorKey,
      initialLocation: '/',
      debugLogDiagnostics: true,
      redirect: (context, state) {
        final isLoggedIn = authProvider.isAuthenticated;
        final isLoggingIn = state.matchedLocation == '/login';
        final isRegistering = state.matchedLocation == '/register';
        
        _logger.info('Route check: ${state.matchedLocation} - Auth state: $isLoggedIn');

        // If not logged in and not on login or register page, redirect to login
        if (!isLoggedIn && !isLoggingIn && !isRegistering) {
          _logger.info('Redirecting to login from ${state.matchedLocation}');
          return '/login';
        }
        
        // If logged in and on login or register page, redirect to home
        if (isLoggedIn && (isLoggingIn || isRegistering)) {
          _logger.info('Redirecting to home from ${state.matchedLocation}');
          return '/';
        }
        
        // No redirect needed
        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => HomeScreen(),
        ),
        GoRoute(
          path: '/notebooks',
          builder: (context, state) => NotebooksScreen(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) => NotebookDetailScreen(
                notebookId: state.pathParameters['id']!,
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/notes',
          builder: (context, state) => NotesScreen(),
        ),
        GoRoute(
          path: '/tasks',
          builder: (context, state) => TasksScreen(),
        ),
        GoRoute(
          path: '/trash',
          builder: (context, state) => TrashScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => LoginScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => RegisterScreen(),
        ),
      ],
      refreshListenable: authProvider,
    );
  }
}
