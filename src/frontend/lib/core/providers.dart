import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import '../providers/notes_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/notebooks_provider.dart';  // Add this import

class AppProviders {
  static final providers = [
    ChangeNotifierProvider(create: (_) => NotebooksProvider()),
    ChangeNotifierProvider(create: (_) => NotesProvider()),
    ChangeNotifierProvider(create: (_) => TasksProvider()),
  ];
}
