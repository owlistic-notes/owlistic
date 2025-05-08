import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../viewmodel/login_viewmodel.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/register_screen.dart';
import '../screens/notebooks_screen.dart';
import '../screens/notebook_detail_screen.dart';
import '../screens/notes_screen.dart';
import '../screens/tasks_screen.dart';
import '../screens/trash_screen.dart';
import '../utils/logger.dart';

class AppRouter {
  final Logger _logger = Logger('AppRouter');
  
  late final GoRouter router;

  AppRouter(BuildContext context) {
    router = GoRouter(
      refreshListenable: GoRouterRefreshStream(),
      debugLogDiagnostics: true,
      initialLocation: '/',
      redirect: (BuildContext context, GoRouterState state) {
        // Use LoginViewModel for isLoggedIn check
        final loginViewModel = Provider.of<LoginViewModel>(context, listen: false);
        final bool isLoggedIn = loginViewModel.isLoggedIn;
        final bool isLoggingIn = state.fullPath == '/login';
        final bool isRegistering = state.fullPath == '/register';
        
        _logger.debug('GoRouter redirect: isLoggedIn=$isLoggedIn, currentPath=${state.fullPath}');
        
        // If not logged in and not on login or register page, redirect to login
        if (!isLoggedIn && !isLoggingIn && !isRegistering) {
          return '/login';
        }
        
        // If logged in and on login or register page, redirect to home
        if (isLoggedIn && (isLoggingIn || isRegistering)) {
          return '/';
        }
        
        // No redirection needed
        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/notebooks',
          builder: (context, state) => const NotebooksScreen(),
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
          builder: (context, state) => const NotesScreen(),
        ),
        GoRoute(
          path: '/tasks',
          builder: (context, state) => const TasksScreen(),
        ),
        GoRoute(
          path: '/trash',
          builder: (context, state) => const TrashScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
        ),
      ],
    );
  }
}

// Helper class to convert Stream to Listenable for GoRouter
class GoRouterRefreshStream extends ChangeNotifier {
  // ...existing code...
}
