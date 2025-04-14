import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/home_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/tasks_screen.dart';

void main() async {
  await dotenv.load(fileName: ".env");
  runApp(ThinkStackApp());
}

class ThinkStackApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ThinkStack',
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: '/',
      routes: {
        '/': (context) => HomeScreen(),
        '/notes': (context) => NotesScreen(),
        '/tasks': (context) => TasksScreen(),
      },
    );
  }
}
