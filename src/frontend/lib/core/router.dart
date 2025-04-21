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
        // Non-auth routes that don't require authentication
        final publicRoutes = ['/login', '/register'];
        final isLoggingIn = state.matchedLocation == '/login';
        final isRegistering = state.matchedLocation == '/register';
        final isPublicRoute = publicRoutes.contains(state.matchedLocation);
        
        // Auth state
        final isLoggedIn = authProvider.isLoggedIn;
        final isInitializing = authProvider.isLoading;
        
        _logger.info('Route check: ${state.matchedLocation} - Auth state: $isLoggedIn');
        
        // If we're still initializing auth, don't redirect
        if (isInitializing && !isPublicRoute) {
          _logger.info('Auth is initializing, holding at current route');
          return null;
        }

        // If not logged in and trying to access a protected route, redirect to login
        if (!isLoggedIn && !isPublicRoute) {
          _logger.info('Not authenticated, redirecting to login from ${state.matchedLocation}');
          return '/login';
        }
        
        // If logged in and trying to access login or register, redirect to home
        if (isLoggedIn && isPublicRoute) {
          _logger.info('Already authenticated, redirecting to home from ${state.matchedLocation}');
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
