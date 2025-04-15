import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/notes_screen.dart';
import '../screens/tasks_screen.dart';

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => HomeScreen(),
      ),
      GoRoute(
        path: '/notes',
        builder: (context, state) => NotesScreen(),
      ),
      GoRoute(
        path: '/tasks',
        builder: (context, state) => TasksScreen(),
      ),
    ],
  );
}
