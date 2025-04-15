import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'providers/notes_provider.dart';
import 'providers/tasks_provider.dart';
import 'screens/home_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/tasks_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const ThinkStackApp());
}

class ThinkStackApp extends StatelessWidget {
  const ThinkStackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NotesProvider()),
        ChangeNotifierProvider(create: (_) => TasksProvider()),
      ],
      child: MaterialApp(
        title: 'ThinkStack',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => HomeScreen(),
          '/notes': (context) => NotesScreen(),
          '/tasks': (context) => TasksScreen(),
        },
      ),
    );
  }
}
