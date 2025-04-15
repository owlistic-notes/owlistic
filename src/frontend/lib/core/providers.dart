import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import '../providers/notes_provider.dart';
import '../providers/tasks_provider.dart';

class AppProviders {
  static final providers = [
    ChangeNotifierProvider(create: (_) => NotesProvider()),
    ChangeNotifierProvider(create: (_) => TasksProvider()),
  ];
}
