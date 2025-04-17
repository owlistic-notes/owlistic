import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/notes_screen.dart';
import '../screens/tasks_screen.dart';
import '../screens/notebooks_screen.dart';
import '../screens/notebook_detail_screen.dart';

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
      GoRoute(
        path: '/notebooks',
        builder: (context, state) => NotebooksScreen(),
      ),
      GoRoute(
        path: '/notebooks/:id',
        builder: (context, state) => NotebookDetailScreen(
          notebookId: state.pathParameters['id']!,
        ),
      ),
    ],
  );
}
