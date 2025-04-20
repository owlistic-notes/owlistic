import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/notebooks_screen.dart';
import '../screens/notebook_detail_screen.dart';
import '../screens/notes_screen.dart';
import '../screens/tasks_screen.dart';
import '../screens/trash_screen.dart';

/// App Router definition using GoRouter
class AppRouter {
  static final router = GoRouter(
    initialLocation: '/',
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
      // Add trash route
      GoRoute(
        path: '/trash',
        builder: (context, state) => TrashScreen(),
      ),
    ],
  );
}
