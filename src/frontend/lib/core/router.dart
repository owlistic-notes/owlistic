import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:owlistic/viewmodel/login_viewmodel.dart';
import 'package:owlistic/screens/home_screen.dart';
import 'package:owlistic/screens/login_screen.dart';
import 'package:owlistic/screens/register_screen.dart';
import 'package:owlistic/screens/notebooks_screen.dart';
import 'package:owlistic/screens/notebook_detail_screen.dart';
import 'package:owlistic/screens/notes_screen.dart';
import 'package:owlistic/screens/note_editor_screen.dart';
import 'package:owlistic/screens/tasks_screen.dart';
import 'package:owlistic/screens/trash_screen.dart';
import 'package:owlistic/screens/user_profile_screen.dart';
import 'package:owlistic/utils/logger.dart';

class AppRouter {
  final Logger _logger = Logger('AppRouter');
  
  late final GoRouter router;

  AppRouter(BuildContext context, {Stream<dynamic>? authStateChanges}) {
    router = GoRouter(
      refreshListenable: authStateChanges != null 
          ? GoRouterRefreshStream(authStateChanges)
          : GoRouterRefreshStream(),
      debugLogDiagnostics: true,
      initialLocation: '/',
      redirect: (BuildContext context, GoRouterState state) {
        final loginViewModel = context.read<LoginViewModel>();
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
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/notebooks',
          builder: (context, state) => const NotebooksScreen(),
        ),
        GoRoute(
          path: '/notebooks/:id',
          builder: (context, state) {
            final String notebookId = state.pathParameters['id']!;
            return NotebookDetailScreen(notebookId: notebookId);
          },
        ),
        GoRoute(
          path: '/notes',
          builder: (context, state) => const NotesScreen(),
        ),
        GoRoute(
          path: '/notes/:id',
          builder: (context, state) {
            final String noteId = state.pathParameters['id']!;
            return NoteEditorScreen(noteId: noteId);
          },
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
          path: '/profile',
          builder: (context, state) => const UserProfileScreen(),
        ),
      ],
    );
  }
}

// Helper class to convert Stream to Listenable for GoRouter
class GoRouterRefreshStream extends ChangeNotifier {
  late final Stream<dynamic>? _stream;
  StreamSubscription<dynamic>? _subscription;

  GoRouterRefreshStream([Stream<dynamic>? stream]) : _stream = stream {
    _subscription = _stream?.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
