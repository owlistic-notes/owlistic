import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import '../providers/websocket_provider.dart';
import '../providers/block_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/notebooks_provider.dart';
import '../providers/tasks_provider.dart';

/// List of providers used in the app
/// These providers also act as presenters in the MVP pattern
List<SingleChildWidget> appProviders = [
  // Core WebSocket provider is the foundation for real-time updates
  ChangeNotifierProvider<WebSocketProvider>(
    create: (_) => WebSocketProvider(),
  ),
  
  // Domain providers act as presenters in our MVP pattern
  ChangeNotifierProxyProvider<WebSocketProvider, NotebooksProvider>(
    create: (_) => NotebooksProvider(),
    update: (_, webSocketProvider, previousProvider) {
      final provider = previousProvider ?? NotebooksProvider();
      provider.setWebSocketProvider(webSocketProvider);
      return provider;
    },
  ),
  
  ChangeNotifierProxyProvider<WebSocketProvider, NotesProvider>(
    create: (_) => NotesProvider(),
    update: (_, webSocketProvider, previousProvider) {
      final provider = previousProvider ?? NotesProvider();
      provider.setWebSocketProvider(webSocketProvider);
      return provider;
    },
  ),
  
  ChangeNotifierProxyProvider<WebSocketProvider, TasksProvider>(
    create: (_) => TasksProvider(),
    update: (_, webSocketProvider, previousProvider) {
      final provider = previousProvider ?? TasksProvider();
      provider.setWebSocketProvider(webSocketProvider);
      return provider;
    },
  ),
  
  ChangeNotifierProxyProvider<WebSocketProvider, BlockProvider>(
    create: (_) => BlockProvider(),
    update: (_, webSocketProvider, previousProvider) {
      final provider = previousProvider ?? BlockProvider();
      provider.setWebSocketProvider(webSocketProvider);
      return provider;
    },
  ),
];
