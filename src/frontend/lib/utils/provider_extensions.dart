import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/websocket_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/notebooks_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/block_provider.dart';

/// MVP Pattern extensions to make providers work as presenters
extension PresenterExtension on ChangeNotifier {
  /// Mark this presenter as active when its view becomes visible
  void activate() {
    if (this is WebSocketProvider) {
      (this as WebSocketProvider).ensureConnected();
    }
    notifyListeners();
  }
  
  /// Mark this presenter as inactive when its view is no longer visible
  void deactivate() {
    // Any cleanup logic
    notifyListeners();
  }
}

/// Extension methods for WebSocketProvider
extension WebSocketProviderExtension on WebSocketProvider {
  /// Ensures connection and subscribes to a resource in one step
  Future<void> connectAndSubscribe(String resource, {String? id}) async {
    await ensureConnected();
    subscribe(resource, id: id);
  }
  
  /// Reconnects and resubscribes to a set of resources
  Future<void> reconnectWith(List<String> resources, {Map<String, String>? resourceIds}) async {
    await reconnect();
    
    for (final resource in resources) {
      if (resourceIds != null && resourceIds.containsKey(resource)) {
        subscribe(resource, id: resourceIds[resource]);
      } else {
        subscribe(resource);
      }
    }
  }
}

/// Extension to simplify getting providers and treat them as presenters
extension BuildContextProviderExtension on BuildContext {
  /// Get the WebSocketProvider with proper typing and listening preference
  WebSocketProvider webSocketProvider({bool listen = false}) {
    return Provider.of<WebSocketProvider>(this, listen: listen);
  }
  
  /// Get the NotesProvider with proper typing and listening preference
  NotesProvider notesPresenter({bool listen = false}) {
    return Provider.of<NotesProvider>(this, listen: listen);
  }
  
  /// Get the NotebooksProvider with proper typing and listening preference
  NotebooksProvider notebooksPresenter({bool listen = false}) {
    return Provider.of<NotebooksProvider>(this, listen: listen);
  }
  
  /// Get the TasksProvider with proper typing and listening preference
  TasksProvider tasksPresenter({bool listen = false}) {
    return Provider.of<TasksProvider>(this, listen: listen);
  }
  
  /// Get the BlockProvider with proper typing and listening preference
  BlockProvider blockPresenter({bool listen = false}) {
    return Provider.of<BlockProvider>(this, listen: listen);
  }
  
  /// Get any provider with explicit typing, treating it as a presenter
  T presenter<T extends ChangeNotifier>({bool listen = false}) {
    return Provider.of<T>(this, listen: listen);
  }
}
